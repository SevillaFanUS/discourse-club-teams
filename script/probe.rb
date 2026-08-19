# frozen_string_literal: true

# Dumps one raw fixture from the API so the response shape can be
# verified against what this plugin expects, rather than assumed.
#
#   su discourse -c "RAILS_ENV=production bin/rails runner \
#     plugins/discourse-club-teams/script/probe.rb <team_id>"

team_id = ARGV[0]
if team_id.blank?
  puts "Usage: probe.rb <team_id>   (find ids with find_teams.rb)"
  exit 1
end

client = ClubTeams::ApiFootballClient.new(SiteSetting.club_teams_api_key)
season = SiteSetting.club_teams_season.presence ||
  (Time.zone.now.month >= 6 ? Time.zone.now.year : Time.zone.now.year - 1)

fixtures = client.team_fixtures(team_id: team_id.to_i, season: season.to_i)

if fixtures.nil?
  puts "Request failed — check the log."
  exit 1
end

puts "season #{season}: #{fixtures.size} fixture(s), quota left #{client.last_quota_remaining || "?"}"
puts

sample = fixtures.first
if sample.nil?
  puts "No fixtures returned. Wrong season, or the team isn't covered."
  exit 0
end

puts "Fields this plugin reads:"
puts "  fixture.date          #{sample.dig("fixture", "date").inspect}"
puts "  fixture.status.short  #{sample.dig("fixture", "status", "short").inspect}"
puts "  league.name           #{sample.dig("league", "name").inspect}"
puts "  teams.home.name       #{sample.dig("teams", "home", "name").inspect}"
puts "  teams.home.winner     #{sample.dig("teams", "home", "winner").inspect}"
puts "  teams.away.name       #{sample.dig("teams", "away", "name").inspect}"
puts "  goals.home / away     #{sample.dig("goals", "home").inspect} / #{sample.dig("goals", "away").inspect}"
puts
puts "Any nil above means the shape differs and the digest needs adjusting."
