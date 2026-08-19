# frozen_string_literal: true

require "net/http"
require "json"

module ::ClubTeams
  # Thin API-Football (api-sports.io) v3 client.
  #
  # Two things about this API worth knowing, both handled below:
  #   * It returns HTTP 200 with a populated "errors" field for things
  #     like an invalid key or an out-of-plan request, so a 2xx status
  #     alone doesn't mean success.
  #   * "errors" is an object when there are errors and an empty array
  #     when there aren't, so it can't be tested with .any? alone.
  class ApiFootballClient
    BASE_URL = "https://v3.football.api-sports.io"

    def initialize(api_key)
      @api_key = api_key
    end

    # Whole season for one team, in one request — cheaper than separate
    # "last" and "next" calls, and the split is trivial locally.
    def team_fixtures(team_id:, season:)
      get("/fixtures", team: team_id, season: season)
    end

    def search_teams(name)
      get("/teams", search: name)
    end

    # Remaining daily quota, straight from the response headers. Useful
    # when running against a 100/day free tier.
    attr_reader :last_quota_remaining

    # Why the last call failed, in words. A diagnostic tool that says
    # "check the log" isn't much of a diagnostic tool.
    attr_reader :last_error

    # Raw status and body of the last call, for probing.
    attr_reader :last_status, :last_body

    private

    def get(path, params = {})
      @last_error = nil
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
        @last_error = "HTTP #{response.code} — #{response.body.to_s[0, 300]}"
        log("#{path}: #{@last_error}")
        return nil
      end

      body = JSON.parse(response.body)

      # A populated "errors" arrives with HTTP 200, so this is a real
      # failure path, not an edge case.
      errors = body["errors"]
      if errors.is_a?(Hash) && errors.any?
        @last_error = "API rejected the request: #{errors.map { |k, v| "#{k}: #{v}" }.join("; ")}"
        log("#{path}: #{@last_error}")
        return nil
      end

      body["response"]
    rescue => e
      @last_error = "#{e.class}: #{e.message}"
      log("#{path}: #{@last_error}")
      nil
    end

    def log(message)
      Rails.logger.warn("[#{::ClubTeams::PLUGIN_NAME}] #{message}")
    end
  end
end
