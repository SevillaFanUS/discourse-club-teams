# frozen_string_literal: true

require "net/http"
require "json"
require "time"

module ::ClubTeams
  module Providers
    # ESPN's public site API. No key, no registration, no quota — and,
    # unlike API-Football's free tier, no restriction to past seasons.
    #
    # It is undocumented and unsupported, so treat every field as
    # optional and never let a missing one raise.
    #
    # Fixtures come from the league scoreboard over a date range rather
    # than from teams/{id}/schedule, which returns an empty events array
    # for Liga F. One request per league per run.
    class Espn < Base
      BASE_URL = "https://site.api.espn.com/apis/site/v2/sports/soccer"

      # A team can play in more than one competition, so leagues is a
      # list. Liga F alone is the sensible minimum for a women's side.
      FALLBACK_LEAGUES = %w[esp.w.1].freeze

      def self.needs_key?
        false
      end

      def fixtures(team_id:, leagues: [], back_days: 150, forward_days: 90)
        @last_error = nil

        wanted = leagues.empty? ? FALLBACK_LEAGUES : leagues
        window = date_range(back_days, forward_days)

        by_league = {}
        failures = []

        wanted.each do |league|
          events = scoreboard(league, window)

          if events.nil?
            failures << league
            next
          end

          by_league[league] = events
        end

        # Every league failed: report nothing rather than a misleading
        # empty list, so the caller can leave the existing post alone.
        return fail!("no league responded (#{failures.join(", ")})") if failures.size == wanted.size

        normalise(by_league, team_id)
      end

      # Everything between "raw JSON" and "fixtures the digest can use",
      # with no network in it. Kept separate so script/check.rb can
      # exercise the real path against captured responses.
      def normalise(events_by_league, team_id)
        events_by_league
          .flat_map do |league, events|
            Array(events).filter_map do |event|
              fixture = build_fixture(event, league)
              next if fixture.nil?
              next if fixture.side_for(team_id).nil?

              fixture
            end
          end
          .sort_by { |f| f.kickoff || Time.at(0) }
      end

      private

      def date_range(back_days, forward_days)
        now = Time.now.utc
        from = (now - (back_days * 86_400)).strftime("%Y%m%d")
        to = (now + (forward_days * 86_400)).strftime("%Y%m%d")
        "#{from}-#{to}"
      end

      def scoreboard(league, window)
        body = get("/#{league}/scoreboard", dates: window, limit: 400)
        return nil if body.nil?

        events = body["events"]
        events.is_a?(Array) ? events : []
      end

      def build_fixture(event, league)
        competition = Array(event["competitions"]).first
        return nil if competition.nil?

        competitors = Array(competition["competitors"])
        home = competitors.find { |c| c["homeAway"] == "home" }
        away = competitors.find { |c| c["homeAway"] == "away" }
        return nil if home.nil? || away.nil?

        state = map_state(competition.dig("status", "type") || {})

        ::ClubTeams::Fixture.new(
          kickoff: parse_time(competition["date"] || event["date"]),
          state: state,
          home_id: home.dig("team", "id") || home["id"],
          home_name: display_name(home),
          home_score: parse_score(home["score"], state),
          away_id: away.dig("team", "id") || away["id"],
          away_name: display_name(away),
          away_score: parse_score(away["score"], state),
          competition: competition["altGameNote"] || league,
          url: summary_link(event),
        )
      end

      def display_name(competitor)
        competitor.dig("team", "displayName") || competitor.dig("team", "name") ||
          competitor.dig("team", "shortDisplayName") || ""
      end

      def summary_link(event)
        link =
          Array(event["links"]).find { |l| Array(l["rel"]).include?("summary") } ||
            Array(event["links"]).first
        link && link["href"]
      end

      # ESPN reports a scheduled match's score as "0", not null, so a
      # score is only meaningful once the match is under way. Reading it
      # unconditionally would print every upcoming fixture as 0–0.
      def parse_score(value, state)
        return nil unless %i[live finished].include?(state)
        return nil if value.nil? || value.to_s.strip.empty?

        Integer(value.to_s.strip, exception: false)
      end

      # Status names are matched loosely on purpose. The exact vocabulary
      # is undocumented and has grown over time, but the words used for
      # abandonment are stable enough to test as substrings, and the
      # completed / state pair covers everything else.
      def map_state(type)
        name = type["name"].to_s.upcase

        return :postponed if name.include?("POSTPONED") || name.include?("DELAYED")
        if name.include?("CANCEL") || name.include?("ABANDON") || name.include?("FORFEIT")
          return :cancelled
        end
        return :finished if type["completed"] == true

        case type["state"].to_s
        when "in" then :live
        when "pre" then :scheduled
        when "post" then :finished
        else :unknown
        end
      end

      def parse_time(value)
        return nil if value.nil? || value.to_s.empty?

        Time.parse(value.to_s).utc
      rescue ArgumentError, TypeError
        nil
      end

      def get(path, params = {})
        uri = URI("#{BASE_URL}#{path}")
        uri.query = URI.encode_www_form(params)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 20

        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/json"
        request["User-Agent"] = "discourse-club-teams"

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          return fail!("HTTP #{response.code} for #{path}")
        end

        raw = response.body.to_s
        # An unknown league slug comes back 200 with an empty body
        # rather than a 404, which is worth naming precisely.
        return fail!("empty response for #{path} — is the league slug right?") if raw.strip.empty?

        JSON.parse(raw)
      rescue JSON::ParserError => e
        fail!("unparseable response for #{path}: #{e.message}")
      rescue => e
        fail!("#{e.class}: #{e.message}")
      end
    end
  end
end
