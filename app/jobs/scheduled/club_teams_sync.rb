# frozen_string_literal: true

require "digest"

module ::Jobs
  # Refreshes the other-teams post.
  #
  # One request per league per team per run. ESPN publishes no rate
  # limit but asks for restraint, so the default six-hour cadence with
  # two leagues is deliberately modest.
  class ClubTeamsSync < ::Jobs::Scheduled
    every 6.hours

    def execute(_args)
      return unless SiteSetting.club_teams_enabled

      self.class.sync!
    end

    def self.sync!
      return :no_topic if SiteSetting.club_teams_topic_id.to_i <= 0

      specs = ::ClubTeams::TeamSpec.parse_all(SiteSetting.club_teams_teams)
      return :no_teams if specs.empty?

      topic = Topic.find_by(id: SiteSetting.club_teams_topic_id.to_i, deleted_at: nil)
      if topic.nil?
        Rails.logger.warn(
          "[#{::ClubTeams::PLUGIN_NAME}] topic #{SiteSetting.club_teams_topic_id} not found",
        )
        return :no_topic
      end

      fetched = specs.map { |spec| fetch(spec) }

      # A total wipeout is far more likely to be a broken key, an
      # exhausted quota or an outage than every season genuinely being
      # empty. Replacing a good post with "nothing found" would be worse
      # than doing nothing, so leave it alone.
      if fetched.all? { |team| team[:fixtures].empty? }
        reasons = fetched.filter_map { |team| team[:error] }.uniq
        Rails.logger.warn(
          "[#{::ClubTeams::PLUGIN_NAME}] no fixtures for any team; leaving post untouched" +
            (reasons.any? ? " (#{reasons.join("; ")})" : ""),
        )
        return :no_data
      end

      body =
        ::ClubTeams::ResultsDigest.new(
          fetched,
          recent_count: SiteSetting.club_teams_recent_count.to_i,
          upcoming_count: SiteSetting.club_teams_upcoming_count.to_i,
          timezone: timezone,
          heading: SiteSetting.club_teams_heading.presence,
        ).render

      publish(topic, body)
    end

    def self.fetch(spec)
      provider =
        ::ClubTeams::ProviderRegistry.build(spec.provider, api_key: SiteSetting.club_teams_api_key)

      if provider.nil?
        return {
          label: spec.label,
          id: spec.id,
          fixtures: [],
          error: "unknown provider '#{spec.provider}' for #{spec.label}",
        }
      end

      fixtures =
        provider.fixtures(
          team_id: spec.id,
          leagues: spec.leagues,
          back_days: SiteSetting.club_teams_back_days.to_i,
          forward_days: SiteSetting.club_teams_forward_days.to_i,
        )

      {
        label: spec.label,
        id: spec.id,
        fixtures: fixtures || [],
        error: fixtures.nil? ? "#{spec.label}: #{provider.last_error}" : nil,
      }
    end

    def self.timezone
      SiteSetting.club_teams_timezone.presence || "Europe/Madrid"
    end

    def self.publish(topic, body)
      fingerprint = Digest::MD5.hexdigest(body)
      state = PluginStore.get(::ClubTeams::PLUGIN_NAME, "post") || {}

      if state["post_id"].present?
        post = Post.find_by(id: state["post_id"], deleted_at: nil)

        if post
          return :unchanged if state["digest"] == fingerprint

          PostRevisor.new(post, post.topic).revise!(
            Discourse.system_user,
            { raw: body },
            skip_validations: true,
            bypass_bump: true,
            edit_reason: "Results updated",
          )
          save_state(post.id, fingerprint)
          return :updated
        end
      end

      post =
        PostCreator.create!(
          Discourse.system_user,
          topic_id: topic.id,
          raw: body,
          skip_validations: true,
        )

      save_state(post.id, fingerprint)
      :created
    end

    def self.save_state(post_id, fingerprint)
      PluginStore.set(
        ::ClubTeams::PLUGIN_NAME,
        "post",
        { "post_id" => post_id, "digest" => fingerprint },
      )
    end
  end
end
