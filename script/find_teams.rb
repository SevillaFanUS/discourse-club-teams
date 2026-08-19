# frozen_string_literal: true

# Looks up API-Football team ids by name, so club_teams_teams can be
# filled in.
#
#   su discourse -c "RAILS_ENV=production bin/rails runner \
#     plugins/discourse-club-teams/script/find_teams.rb Sevilla"
#
# Costs one API request per search term.

terms = ARGV.presence || %w[Sevilla]

if SiteSetting.club_teams_api_key.blank?
  puts "Set club_teams_api_key first."
  exit 1
end

client = ClubTeams::ApiFootballClient.new(SiteSetting.club_teams_api_key)

terms.each do |term|
  puts "=== #{term} ==="
  results = client.search_teams(term)

  if results.nil?
    puts "  request failed — check the log for details"
    next
  end

  if results.empty?
    puts "  no matches"
    next
  end

  results.each do |row|
    team = row["team"] || {}
    country = team["country"]
    national = team["national"] ? " [national]" : ""
    puts format("  %-8s %-38s %s%s", team["id"], team["name"], country, national)
  end
end

puts
puts "Quota remaining today: #{client.last_quota_remaining || "unknown"}"
puts
puts "Set them with, for example:"
puts "  SiteSetting.club_teams_teams = \"Femenino:1234,Sevilla Atlético:5678\""
