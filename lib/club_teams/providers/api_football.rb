# frozen_string_literal: true

require "net/http"
require "json"
require "time"

module ::ClubTeams
  module Providers
    # API-Football (api-sports.io) v3.
    #
    # Kept for leagues ESPN doesn't carry, but note the free plan only
    # serves historical seasons — currently 2022 to 2024 — and returns
    # HTTP 200 with a populated "errors" object for anything newer. A
    # paid plan is required for a current season.
    class ApiFootball < Base
      BASE_URL = "https://v3.football.api-sports.io"

      FINISHED = %w[FT AET PEN].freeze
      LIVE = %w[1H HT 2H ET BT P LIVE INT].freeze
      POSTPONED = %w[PST TBD].freeze
      CANCELLED = %w[CANC ABD AWD WO].freeze

      attr_reader :last_quota_remaining, :last_status, :last_body

      def initialize(api_key = nil)
        @api_key = api_key.to_s
      end

      def fixtures(team_id:, leagues: [], back_days: 150, forward_days: 90)
        @last_error = nil

        return fail!("no API key configured") if @api_key.empty?

        raw = get("/fixtures", team: team_id, season: season_for(back_days))
        return nil if raw.nil?

        raw.filter_map { |item| build_fixture(item) }.sort_by { |f| f.kickoff || Time.at(0) }
      end

      def search_teams(name)
        get("/teams", search: name)
      end

      private

      # API-Football indexes by season year rather than by date, so a
      # window has to be turned back into a season. European seasons roll
      # over in June.
      def season_for(_back_days)
        now = Time.now.utc
        now.month >= 6 ? now.year : now.year - 1
      end

      def build_fixture(item)
        short = item.dig("fixture", "status", "short").to_s

        ::ClubTeams::Fixture.new(
          kickoff: parse_time(item.dig("fixture", "date")),
          state: map_state(short),
          home_id: item.dig("teams", "home", "id"),
          home_name: item.dig("teams", "home", "name"),
          home_score: item.dig("goals", "home"),
          away_id: item.dig("teams", "away", "id"),
          away_name: item.dig("teams", "away", "name"),
          away_score: item.dig("goals", "away"),
          competition: item.dig("league", "name"),
          url: nil,
        )
      rescue StandardError
        nil
      end

      def map_state(short)
        return :finished if FINISHED.include?(short)
        return :live if LIVE.include?(short)
        return :postponed if POSTPONED.include?(short)
        return :cancelled if CANCELLED.include?(short)
        return :scheduled if short == "NS"

        :unknown
      end

      def parse_time(value)
        return nil if value.nil? || value.to_s.empty?

        Time.parse(value.to_s).utc
      rescue ArgumentError, TypeError
        nil
      end

      def get(path, params = {})
        @last_status = nil
        @last_body = nil

        uri = URI("#{BASE_URL}#{path}")
        uri.query = URI.encode_www_form(params)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 20

        request = Net::HTTP::Get.new(uri)
        request["x-apisports-key"] = @api_key

        response = http.request(request)
        @last_quota_remaining = response["x-ratelimit-requests-remaining"]
        @last_status = response.code
        @last_body = response.body.to_s

        unless response.is_a?(Net::HTTPSuccess)
          return fail!("HTTP #{response.code} — #{response.body.to_s[0, 300]}")
        end

        body = JSON.parse(response.body)

        # A populated "errors" arrives with HTTP 200, so this is a real
        # failure path rather than an edge case. It is an object when
        # there are errors and an empty array when there aren't, so it
        # cannot be tested with .any? alone.
        errors = body["errors"]
        if errors.is_a?(Hash) && errors.any?
          return fail!("API rejected the request: #{errors.map { |k, v| "#{k}: #{v}" }.join("; ")}")
        end

        body["response"]
      rescue => e
        fail!("#{e.class}: #{e.message}")
      end
    end
  end
end
