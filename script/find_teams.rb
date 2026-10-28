# frozen_string_literal: true

# Lists the teams in an ESPN league so you can find an id.
#
#   bin/rails runner plugins/discourse-club-teams/script/find_teams.rb esp.w.1
#   bin/rails runner plugins/discourse-club-teams/script/find_teams.rb esp.w.1 sevilla
#
# Names in the API rarely match what you would guess — a women's side is
# often just "Sevilla", the reserves "Sevilla Atletico" without the
# accent — so search on a fragment and read the list.

require "net/http"
require "json"

league = ARGV[0]
filter = ARGV[1].to_s.downcase

if league.to_s.empty?
  puts "Usage: find_teams.rb <league_slug> [name fragment]"
  puts
  puts "Spanish slugs ESPN carries:"
  puts "  esp.1                 LALIGA"
  puts "  esp.2                 LALIGA 2"
  puts "  esp.copa_del_rey      Copa del Rey"
  puts "  esp.w.1               Liga F"
  puts "  esp.copa_de_la_reina  Copa de la Reina"
  puts
  puts "There is no Primera Federacion slug, so club B teams are not available."
  exit 1
end

uri = URI("https://site.api.espn.com/apis/site/v2/sports/soccer/#{league}/teams")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.open_timeout = 10
http.read_timeout = 20

request = Net::HTTP::Get.new(uri)
request["Accept"] = "application/json"
request["User-Agent"] = "discourse-club-teams"

response = http.request(request)

unless response.is_a?(Net::HTTPSuccess)
  puts "HTTP #{response.code} — ESPN rejected the request."
  exit 1
end

raw = response.body.to_s
if raw.strip.empty?
  puts "Empty response. ESPN returns an empty body rather than a 404 for a league"
  puts "slug it does not carry, so '#{league}' is almost certainly wrong."
  exit 1
end

body = JSON.parse(raw)
entries = body.dig("sports", 0, "leagues", 0, "teams") || []
league_name = body.dig("sports", 0, "leagues", 0, "name") || league

puts "#{league_name} — #{entries.size} teams"
puts

entries.each do |entry|
  team = entry["team"] || {}
  name = team["displayName"].to_s
  next if !filter.empty? && !name.downcase.include?(filter)

  puts format("  %-8s %s", team["id"], name)
end

puts
puts "Use it as:  Label|espn|<id>|#{league}"
