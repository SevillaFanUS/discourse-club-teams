# frozen_string_literal: true

# Refreshes the post immediately instead of waiting for the six-hourly job.
#
#   su discourse -c "RAILS_ENV=production bin/rails runner \
#     plugins/discourse-club-teams/script/sync_now.rb"

result = Jobs::ClubTeamsSync.sync!
puts "result: #{result}"

case result
when :not_configured then puts "Set club_teams_api_key."
when :no_topic       then puts "Set club_teams_topic_id to an existing topic."
when :no_teams       then puts "Set club_teams_teams, e.g. \"Femenino:1234,Sevilla Atlético:5678\"."
when :no_data        then puts "No fixtures came back — check the key, quota, and team ids."
end
