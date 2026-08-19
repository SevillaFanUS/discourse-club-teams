# frozen_string_literal: true

require "digest"

module ::Jobs
  # Refreshes the other-teams post. One API request per configured team
  # per run; at four runs a day with three teams that's 12 of the free
  # tier's 100.
  class ClubTeamsSync < ::Jobs::Scheduled
    every 6.hours

    def execute(_args)
      return unless SiteSetting.club_teams_enabled

      self.class.sync!
    end

    def self.sync!
      return :not_configured if SiteSetting.club_teams_api_key.blank?
      return :no_topic if SiteSetting.club_teams_topic_id.to_i <= 0

      teams = parse_teams
      return :no_teams if teams.empty?

      topic = Topic.find_by(id: SiteSetting.club_teams_topic_id.to_i, deleted_at: nil)
      if topic.nil?
        Rails.logger.warn("[#{::ClubTeams::PLUGIN_NAME}] topic #{SiteSetting.club_teams_topic_id} not found")
        return :no_topic
      end

      season = resolved_season
      client = ::ClubTeams::ApiFootballClient.new(SiteSetting.club_teams_api_key)

      fetched =
        teams.map do |team|
          fixtures = client.team_fixtures(team_id: team[:id], season: season)
          { label: team[:label], id: team[:id], fixtures: fixtures || [] }
        end

      # A total wipeout — every team failed — is far more likely to be a
      # bad key or exhausted quota than genuinely empty seasons. Leave
      # the existing post alone rather than replacing it with "nothing
      # found".
      if fetched.all? { |t| t[:fixtures].empty? }
        Rails.logger.warn("[#{::ClubTeams::PLUGIN_NAME}] no fixtures for any team; leaving post untouched")
        return :no_data
      end

      body =
        ::ClubTeams::ResultsDigest.new(
          fetched,
          recent_count: SiteSetting.club_teams_recent_count.to_i,
          upcoming_count: SiteSetting.club_teams_upcoming_count.to_i,
          timezone: SiteSetting.club_teams_timezone.presence || "Europe/Madrid",
          season_label: season_label(season),
        ).render

      publish(topic, body)
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

    # "Femenino:1234, Sevilla Atlético:5678"
    #
    # Split on the LAST colon: a label may legitimately contain one
    # ("Femenino: Liga F"), but the id is always the trailing segment.
    def self.parse_teams
      SiteSetting.club_teams_teams.to_s.split(",").filter_map do |pair|
        index = pair.rindex(":")
        next if index.nil?

        label = pair[0...index].strip
        id = pair[(index + 1)..].to_s.strip
        next if label.empty? || id.to_i <= 0

        { label: label, id: id.to_i }
      end
    end

    def self.resolved_season
      override = SiteSetting.club_teams_season
      return override.to_i if override.present?

      now = Time.zone.now
      now.month >= 6 ? now.year : now.year - 1
    end

    def self.season_label(season)
      "#{season}/#{(season + 1).to_s[-2..]}"
    end
  end
end
