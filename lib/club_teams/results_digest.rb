# frozen_string_literal: true

module ::ClubTeams
  # Turns normalised fixtures into the post body: one section per team,
  # recent results then upcoming fixtures.
  class ResultsDigest
    # @param teams [Array<Hash>] { label:, id:, fixtures: [Fixture] }
    def initialize(teams, recent_count:, upcoming_count:, timezone:, heading: nil)
      @teams = teams
      @recent_count = recent_count
      @upcoming_count = upcoming_count
      @timezone = timezone
      @heading = heading || "Beyond the first team"
    end

    def render
      sections = @teams.map { |team| team_section(team) }.compact

      return nothing_yet if sections.empty?

      <<~MARKDOWN.strip
        # #{@heading}

        #{sections.join("\n\n")}

        *Updated automatically. Times shown in #{friendly_zone}.*
      MARKDOWN
    end

    private

    def friendly_zone
      @timezone.to_s.split("/").last.to_s.tr("_", " ")
    end

    def nothing_yet
      <<~MARKDOWN.strip
        # #{@heading}

        No fixtures found yet. This fills in once the seasons are under way.
      MARKDOWN
    end

    def team_section(team)
      fixtures = Array(team[:fixtures])
      return nil if fixtures.empty?

      team_id = team[:id]
      played = fixtures.select(&:played?)
      upcoming = fixtures.reject { |f| f.played? || f.called_off? }

      parts = ["## #{team[:label]}"]

      if played.any?
        parts << ""
        parts << results_table(played.last(@recent_count).reverse, team_id)
      end

      if @upcoming_count.positive? && upcoming.any?
        parts << ""
        parts << "**Next up**"
        parts << ""
        parts << fixtures_table(upcoming.first(@upcoming_count))
      end

      # A team with neither a result nor a fixture in the window adds
      # nothing but a bare heading.
      return nil if parts.size == 1

      parts.join("\n")
    end

    def results_table(fixtures, team_id)
      rows =
        fixtures.map do |fixture|
          "| #{short_date(fixture)} | #{escape(fixture.home_name)} #{fixture.score_line} " \
            "#{escape(fixture.away_name)} | #{outcome_cell(fixture, team_id)} |"
        end

      <<~TABLE.strip
        | | Result | |
        | --- | --- | --- |
        #{rows.join("\n")}
      TABLE
    end

    def fixtures_table(fixtures)
      rows =
        fixtures.map do |fixture|
          "| #{kickoff(fixture)} | #{escape(fixture.home_name)} v #{escape(fixture.away_name)} |"
        end

      <<~TABLE.strip
        | | |
        | --- | --- |
        #{rows.join("\n")}
      TABLE
    end

    # Wins are bolded, everything else left plain — a table of bold text
    # emphasises nothing.
    def outcome_cell(fixture, team_id)
      outcome = fixture.outcome_for(team_id)
      return "" if outcome.nil?

      outcome == "Win" ? "**Win**" : outcome
    end

    def short_date(fixture)
      return "" if fixture.kickoff.nil?

      local(fixture.kickoff).strftime("%-d %b")
    rescue StandardError
      ""
    end

    def kickoff(fixture)
      return "TBC" if fixture.kickoff.nil?

      local(fixture.kickoff).strftime("%a %-d %b, %-I:%M %p")
    rescue StandardError
      "TBC"
    end

    # ActiveSupport when it is there (Discourse), plain UTC when it is
    # not (the offline check script).
    def local(time)
      time.respond_to?(:in_time_zone) ? time.in_time_zone(@timezone) : time
    end

    def escape(text)
      text.to_s.gsub("|", "\\|")
    end
  end
end
