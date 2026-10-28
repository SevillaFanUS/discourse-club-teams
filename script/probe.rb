# frozen_string_literal: true

# Confirms a team really has data before you trust the post.
#
#   bin/rails runner plugins/discourse-club-teams/script/probe.rb espn 21424 esp.w.1
#   bin/rails runner plugins/discourse-club-teams/script/probe.rb 21424
#
# Prints the exact fields the digest reads. A nil where a value is
# expected means the provider's shape has drifted.

args = ARGV.dup
provider_name = ::ClubTeams::ProviderRegistry.known?(args.first) ? args.shift : "espn"
team_id = args.shift
leagues = args.flat_map { |a| a.split(",") }.map(&:strip).reject(&:empty?)

if team_id.to_s.empty?
  puts "Usage: probe.rb [provider] <team_id> [league,league]"
  puts "Providers: #{::ClubTeams::ProviderRegistry.names.join(", ")}"
  exit 1
end

provider = ::ClubTeams::ProviderRegistry.build(provider_name, api_key: SiteSetting.club_teams_api_key)

puts "provider:  #{provider_name}"
puts "team id:   #{team_id}"
puts "leagues:   #{leagues.any? ? leagues.join(", ") : "(provider default)"}"
puts "key set:   #{SiteSetting.club_teams_api_key.to_s.empty? ? "no" : "yes"}"
puts

fixtures = provider.fixtures(team_id: team_id, leagues: leagues)

if fixtures.nil?
  puts "FAILED: #{provider.last_error}"
  puts
  puts "Common causes:"
  puts "  * wrong league slug   -> ESPN returns an empty body for slugs it does not carry"
  puts "  * key rejected        -> api_football only; check it at api-sports.io"
  puts "  * out-of-plan season  -> api_football free plans cannot serve the current season"
  puts "  * connection error    -> the container could not reach the provider"
  exit 1
end

if fixtures.empty?
  puts "The request worked but no fixtures matched team #{team_id}."
  puts "Either the id belongs to another club, or nothing falls inside the date window."
  exit 0
end

played = fixtures.select(&:played?)
upcoming = fixtures.reject { |f| f.played? || f.called_off? }

puts "#{fixtures.size} fixtures — #{played.size} played, #{upcoming.size} upcoming"
puts

(played.last(3) + upcoming.first(3)).each do |f|
  puts "  kickoff:     #{f.kickoff.inspect}"
  puts "  state:       #{f.state}"
  puts "  home:        #{f.home_name.inspect} (#{f.home_id}) #{f.home_score.inspect}"
  puts "  away:        #{f.away_name.inspect} (#{f.away_id}) #{f.away_score.inspect}"
  puts "  competition: #{f.competition.inspect}"
  puts "  outcome:     #{f.outcome_for(team_id).inspect}"
  puts "  url:         #{f.url.inspect}"
  puts
end

blank = fixtures.count { |f| f.home_name.empty? || f.away_name.empty? || f.kickoff.nil? }
puts blank.zero? ? "No missing fields." : "WARNING: #{blank} fixtures are missing a name or a kickoff time."
