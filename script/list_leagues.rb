# frozen_string_literal: true

# Lists the leagues API-Football has for a country, and which seasons of
# each your current plan can actually read.
#
#   bin/rails runner plugins/discourse-club-teams/script/list_leagues.rb Spain
#   bin/rails runner plugins/discourse-club-teams/script/list_leagues.rb Spain federacion
#
# League metadata is not season-restricted, so this works on the free
# plan and answers the only question worth paying to resolve: is the
# competition in their dataset at all, and is the current season marked
# as covered?

require "net/http"
require "json"

country = ARGV[0] || "Spain"
filter = ARGV[1].to_s.downcase

key = SiteSetting.club_teams_api_key.to_s

if key.empty?
  puts "club_teams_api_key is not set."
  exit 1
end

uri = URI("https://v3.football.api-sports.io/leagues")
uri.query = URI.encode_www_form(country: country)

http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.open_timeout = 10
http.read_timeout = 20

request = Net::HTTP::Get.new(uri)
request["x-apisports-key"] = key

response = http.request(request)
puts "HTTP #{response.code}   quota left today: #{response["x-ratelimit-requests-remaining"].inspect}"
puts

body = JSON.parse(response.body.to_s)

errors = body["errors"]
if errors.is_a?(Hash) && errors.any?
  puts "API rejected the request: #{errors.map { |k, v| "#{k}: #{v}" }.join("; ")}"
  exit 1
end

entries = body["response"] || []
puts "#{entries.size} competitions listed for #{country}"
puts

entries.each do |entry|
  league = entry["league"] || {}
  name = league["name"].to_s
  next if !filter.empty? && !name.downcase.include?(filter)

  seasons = entry["seasons"] || []
  current = seasons.find { |s| s["current"] }
  years = seasons.map { |s| s["year"] }

  puts format("  %-6s %-42s %s", league["id"], name, league["type"])
  puts "         seasons: #{years.min}-#{years.max} (#{years.size})"
  puts "         current season: #{current ? current["year"] : "none flagged"}"

  if current
    coverage = current["coverage"] || {}
    fixtures = coverage["fixtures"] || {}
    puts "         covers: fixtures=#{!fixtures.empty?} standings=#{coverage["standings"].inspect} " \
           "events=#{fixtures["events"].inspect}"
  end
  puts
end

puts "A competition listed here with the current season flagged is one a paid"
puts "plan could read. Free plans still cannot fetch its fixtures — that limit"
puts "is about the season, not the competition."
