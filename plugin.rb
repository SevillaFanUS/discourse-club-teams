# frozen_string_literal: true

# name: discourse-club-teams
# about: Keeps a single topic updated with recent results and upcoming fixtures for a club's other teams — women's side, reserves, youth.
# version: 0.2.0
# authors: Chris Lail
# url: https://github.com/SevillaFanUS/discourse-club-teams
# required_version: 3.0.0

enabled_site_setting :club_teams_enabled

module ::ClubTeams
  PLUGIN_NAME = "discourse-club-teams"
end

after_initialize do
  # This install does not Zeitwerk-autoload plugin lib/ and app/ files,
  # so everything is required explicitly. Order matters: Fixture before
  # the providers that build them, providers before the registry.
  require_relative "lib/club_teams/fixture"
  require_relative "lib/club_teams/team_spec"
  require_relative "lib/club_teams/providers/base"
  require_relative "lib/club_teams/providers/espn"
  require_relative "lib/club_teams/providers/api_football"
  require_relative "lib/club_teams/provider_registry"
  require_relative "lib/club_teams/results_digest"
  require_relative "app/jobs/scheduled/club_teams_sync"
end
