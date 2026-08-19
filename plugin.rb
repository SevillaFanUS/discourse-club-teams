# frozen_string_literal: true

# name: discourse-club-teams
# about: Keeps a single topic updated with recent results and upcoming fixtures for a club's other teams — women's side, reserves, youth — using API-Football.
# version: 0.1.0
# authors: Chris Lail
# url: https://github.com/SevillaFanUS/discourse-club-teams
# required_version: 3.0.0

enabled_site_setting :club_teams_enabled

module ::ClubTeams
  PLUGIN_NAME = "discourse-club-teams"
end

after_initialize do
  require_relative "lib/club_teams/api_football_client"
  require_relative "lib/club_teams/results_digest"
  require_relative "app/jobs/scheduled/club_teams_sync"
end
