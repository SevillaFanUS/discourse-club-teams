# frozen_string_literal: true

# Offline checks for the parsing and rendering layers. No Rails, no
# network, no database:
#
#   ruby script/check.rb
#
# These exist because three consecutive rebuilds failed on things a
# five-second local check would have caught.

require "json"
require "time"

module ::ClubTeams
  PLUGIN_NAME = "discourse-club-teams"
end

root = File.expand_path("..", __dir__)
require File.join(root, "lib/club_teams/fixture")
require File.join(root, "lib/club_teams/team_spec")
require File.join(root, "lib/club_teams/providers/base")
require File.join(root, "lib/club_teams/providers/espn")
require File.join(root, "lib/club_teams/providers/api_football")
require File.join(root, "lib/club_teams/provider_registry")
require File.join(root, "lib/club_teams/results_digest")

FAILURES = []

def check(name)
  result = yield
  if result == true
    puts "  ok    #{name}"
  else
    puts "  FAIL  #{name}#{result.is_a?(String) ? " — #{result}" : ""}"
    FAILURES << name
  end
rescue => e
  puts "  ERROR #{name} — #{e.class}: #{e.message}"
  FAILURES << name
end

SEVILLA = "21424"

events = JSON.parse(File.read(File.join(root, "spec/fixtures/espn_liga_f.json")))["events"]
espn = ::ClubTeams::Providers::Espn.new
parsed = events.map { |e| espn.send(:build_fixture, e, "esp.w.1") }

# The real path: build, discard other clubs' matches, sort. Deliberately
# fed unsorted input, because ESPN's own ordering is not guaranteed.
ours = espn.normalise({ "esp.w.1" => events }, SEVILLA)

puts "\nESPN parsing"

check("every event parses") { parsed.none?(&:nil?) || "#{parsed.count(&:nil?)} returned nil" }

check("filters out matches we are not in") do
  ours.size == 5 || "expected 5 Sevilla fixtures, got #{ours.size}"
end

check("reads a finished away defeat") do
  f = ours.find { |x| x.away_id == SEVILLA && x.home_name == "Madrid CFF" }
  f.state == :finished && f.home_score == 2 && f.away_score == 0 &&
    f.outcome_for(SEVILLA) == "Loss" || "got #{f&.state} #{f&.score_line} #{f&.outcome_for(SEVILLA)}"
end

check("reads a finished home win") do
  f = ours.find { |x| x.home_id == SEVILLA && x.away_name == "Granada" }
  f.outcome_for(SEVILLA) == "Win" || "got #{f&.outcome_for(SEVILLA)}"
end

# Both sides carry winner:false on a draw, so a provider that trusted
# that flag alone would call a draw a defeat. Scores decide it instead.
check("calls a 1-1 a draw, not a loss") do
  f = ours.find { |x| x.home_name == "Eibar" }
  f.outcome_for(SEVILLA) == "Draw" || "got #{f&.outcome_for(SEVILLA)}"
end

# ESPN reports an unplayed match as score "0", not null.
check("does not invent a 0-0 for a scheduled match") do
  f = ours.find { |x| x.state == :scheduled }
  f.home_score.nil? && f.away_score.nil? && f.score_line == "—" ||
    "got #{f&.home_score.inspect}-#{f&.away_score.inspect}"
end

check("recognises a postponement") do
  f = ours.find { |x| x.home_name == "Sevilla" && x.away_name == "Barcelona" }
  f.state == :postponed && f.called_off? || "got #{f&.state}"
end

check("keeps the match link") do
  f = ours.find { |x| x.home_name == "Madrid CFF" }
  f.url.to_s.include?("gameId/749204") || "got #{f&.url.inspect}"
end

check("sorts by kickoff") do
  times = ours.map(&:kickoff).compact
  times == times.sort || "out of order"
end

check("input really was unsorted, so the sort check means something") do
  raw = parsed.compact.map(&:kickoff)
  raw != raw.sort || "fixture file is pre-sorted; the sort check proves nothing"
end

check("outcome is nil for a team not in the match") do
  parsed.first.outcome_for("99999").nil?
end

puts "\nStatus mapping"

{
  "STATUS_FULL_TIME" => :finished,
  "STATUS_FINAL" => :finished,
  "STATUS_POSTPONED" => :postponed,
  "STATUS_CANCELED" => :cancelled,
  "STATUS_ABANDONED" => :cancelled,
  "STATUS_SCHEDULED" => :scheduled,
}.each do |name, expected|
  check("#{name} -> #{expected}") do
    completed = expected == :finished
    state = { "finished" => "post", "scheduled" => "pre" }[expected.to_s] || "pre"
    got = espn.send(:map_state, { "name" => name, "completed" => completed, "state" => state })
    got == expected || "got #{got}"
  end
end

check("unknown name falls back to state/completed") do
  espn.send(:map_state, { "name" => "STATUS_SOMETHING_NEW", "completed" => true, "state" => "post" }) == :finished
end

check("in-progress reads as live") do
  espn.send(:map_state, { "name" => "STATUS_FIRST_HALF", "completed" => false, "state" => "in" }) == :live
end

puts "\nTeam spec parsing"

check("piped form with leagues") do
  s = ::ClubTeams::TeamSpec.parse("Femenino|espn|21424|esp.w.1;esp.copa_de_la_reina")
  s.label == "Femenino" && s.provider == "espn" && s.id == "21424" &&
    s.leagues == %w[esp.w.1 esp.copa_de_la_reina] || "got #{s.inspect}"
end

check("piped form without leagues") do
  s = ::ClubTeams::TeamSpec.parse("Sevilla Atletico|api_football|5678")
  s.provider == "api_football" && s.leagues.empty? || "got #{s.inspect}"
end

check("legacy colon form still works") do
  s = ::ClubTeams::TeamSpec.parse("Femenino:1234")
  s.provider == "api_football" && s.id == "1234" || "got #{s.inspect}"
end

check("legacy form splits on the last colon") do
  s = ::ClubTeams::TeamSpec.parse("Femenino: Liga F:1234")
  s.label == "Femenino: Liga F" && s.id == "1234" || "got #{s.inspect}"
end

check("parses a full multi-team setting") do
  all = ::ClubTeams::TeamSpec.parse_all("Femenino|espn|21424|esp.w.1, Atletico|api_football|5678")
  all.size == 2 && all[0].provider == "espn" && all[1].provider == "api_football"
end

check("rejects junk") do
  ::ClubTeams::TeamSpec.parse_all("   ,  ,").empty?
end

puts "\nProvider registry"

check("espn needs no key") { ::ClubTeams::Providers::Espn.needs_key? == false }
check("api_football needs a key") { ::ClubTeams::Providers::ApiFootball.needs_key? == true }
check("builds espn") { ::ClubTeams::ProviderRegistry.build("espn").is_a?(::ClubTeams::Providers::Espn) }
check("unknown provider returns nil") { ::ClubTeams::ProviderRegistry.build("nope").nil? }

check("api_football refuses to call without a key") do
  p = ::ClubTeams::ProviderRegistry.build("api_football", api_key: "")
  p.fixtures(team_id: "1").nil? && p.last_error.include?("no API key")
end

puts "\nDigest rendering"

body =
  ::ClubTeams::ResultsDigest.new(
    [{ label: "Femenino", id: SEVILLA, fixtures: ours }],
    recent_count: 3,
    upcoming_count: 2,
    timezone: "Europe/Madrid",
  ).render

check("has the heading") { body.start_with?("# Beyond the first team") }
check("names the team") { body.include?("## Femenino") }
check("shows the win in bold") { body.include?("**Win**") }
check("shows the draw unbolded") { body.include?("| Draw |") }
check("shows a real score") { body.include?("2–0") }
check("no phantom 0-0") { !body.include?("0–0") }
check("has a Next up section") { body.include?("**Next up**") }

check("postponed match is not listed as upcoming") do
  upcoming = body.split("**Next up**").last
  !upcoming.include?("Barcelona") || "postponed fixture leaked into Next up"
end

check("names the timezone readably") { body.include?("Madrid") }

check("a team with no fixtures is dropped, not left as a bare heading") do
  b =
    ::ClubTeams::ResultsDigest.new(
      [{ label: "Femenino", id: SEVILLA, fixtures: ours }, { label: "Ghost", id: "1", fixtures: [] }],
      recent_count: 3,
      upcoming_count: 2,
      timezone: "Europe/Madrid",
    ).render
  !b.include?("## Ghost")
end

check("empty everything renders a placeholder rather than crashing") do
  b =
    ::ClubTeams::ResultsDigest.new(
      [], recent_count: 3, upcoming_count: 2, timezone: "Europe/Madrid"
    ).render
  b.include?("No fixtures found yet")
end

check("pipes in a team name are escaped") do
  f =
    ::ClubTeams::Fixture.new(
      kickoff: Time.now.utc, state: :finished, home_id: "1", home_name: "A|B",
      away_id: SEVILLA, away_name: "Sevilla", home_score: 0, away_score: 1
    )
  b =
    ::ClubTeams::ResultsDigest.new(
      [{ label: "T", id: SEVILLA, fixtures: [f] }],
      recent_count: 3, upcoming_count: 0, timezone: "Europe/Madrid"
    ).render
  b.include?('A\|B')
end

check("upcoming_count 0 hides the section") do
  b =
    ::ClubTeams::ResultsDigest.new(
      [{ label: "Femenino", id: SEVILLA, fixtures: ours }],
      recent_count: 3, upcoming_count: 0, timezone: "Europe/Madrid"
    ).render
  !b.include?("**Next up**")
end

check("recent_count is respected") do
  b =
    ::ClubTeams::ResultsDigest.new(
      [{ label: "Femenino", id: SEVILLA, fixtures: ours }],
      recent_count: 1, upcoming_count: 0, timezone: "Europe/Madrid"
    ).render
  b.scan(/^\| \d/).size == 1 || "got #{b.scan(/^\| \d/).size} result rows"
end

puts
if FAILURES.empty?
  puts "All checks passed."
else
  puts "#{FAILURES.size} failed: #{FAILURES.join(", ")}"
  exit 1
end
