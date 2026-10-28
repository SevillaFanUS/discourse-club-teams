# frozen_string_literal: true

# Publishes or refreshes the post immediately, without waiting for the
# scheduled job.
#
#   bin/rails runner plugins/discourse-club-teams/script/sync_now.rb

unless SiteSetting.club_teams_enabled
  puts "club_teams_enabled is off — turn it on first."
  exit 1
end

result = ::Jobs::ClubTeamsSync.sync!

puts "result: #{result}"

case result
when :created  then puts "Posted for the first time."
when :updated  then puts "Existing post edited in place."
when :unchanged then puts "Nothing changed since the last run; post left alone."
when :no_topic then puts "Set club_teams_topic_id to a real topic."
when :no_teams then puts "club_teams_teams is empty or unparseable."
when :no_data  then puts "Every team came back empty — see the log for why. Post left alone."
end
