# frozen_string_literal: true

module ::ClubTeams
  # Turns API-Football fixture lists into the post body: one section per
  # team, recent results then upcoming fixtures.
  class ResultsDigest
    FINISHED = %w[FT AET PEN].freeze
    LIVE = %w[1H HT 2H ET BT P LIVE].freeze
    CANCELLED = %w[PST CANC ABD AWD WO].freeze

    # @param teams [Array<Hash>] { label:, fixtures: [...] }
    def initialize(teams, recent_count:, upcoming_count:, timezone:, season_label: nil)
      @teams = teams
      @recent_count = recent_count
      @upcoming_count = upcoming_count
      @timezone = timezone
      @season_label = season_label
    end

    def render
      sections = @teams.map { |team| team_section(team) }.compact

      return nothing_yet if sections.empty?

      <<~MARKDOWN.strip
        # Beyond the first team#{@season_label ? " — #{@season_label}" : ""}

        #{sections.join("\n\n")}

        *Updated automatically. Times shown in #{@timezone.sub("_", " ")}.*
      MARKDOWN
    end

    private

    def nothing_yet
      <<~MARKDOWN.strip
        # Beyond the first team

        No fixtures found yet. This fills in once the seasons are under way.
      MARKDOWN
    end

    def team_section(team)
      fixtures = Array(team[:fixtures])
      return nil if fixtures.empty?

      played, upcoming = split(fixtures)

      parts = ["## #{team[:label]}"]

      if played.any?
        parts << ""
        parts << results_table(played.last(@recent_count).reverse, team[:id])
      end

      if @upcoming_count.positive? && upcoming.any?
        parts << ""
        parts << "**Next up**"
        parts << ""
        parts << fixtures_table(upcoming.first(@upcoming_count))
      end

      parts.join("\n")
    end

    # Sorted by kickoff, then partitioned on whether a result exists.
    def split(fixtures)
      sorted = fixtures.sort_by { |f| f.dig("fixture", "date").to_s }

      played = sorted.select { |f| FINISHED.include?(status(f)) }
      upcoming =
        sorted.reject { |f| FINISHED.include?(status(f)) || CANCELLED.include?(status(f)) }

      [played, upcoming]
    end

    def status(fixture)
      fixture.dig("fixture", "status", "short").to_s
    end

    def results_table(fixtures, team_id)
      rows =
        fixtures.map do |f|
          home = f.dig("teams", "home", "name")
          away = f.dig("teams", "away", "name")
          gh = f.dig("goals", "home")
          ga = f.dig("goals", "away")
          score = gh.nil? || ga.nil? ? "—" : "#{gh}–#{ga}"

          "| #{short_date(f)} | #{escape(home)} #{score} #{escape(away)} | #{outcome(f, team_id)} |"
        end

      <<~TABLE.strip
        | | Result | |
        | --- | --- | --- |
        #{rows.join("\n")}
      TABLE
    end

    def fixtures_table(fixtures)
      rows =
        fixtures.map do |f|
          home = f.dig("teams", "home", "name")
          away = f.dig("teams", "away", "name")
          "| #{kickoff(f)} | #{escape(home)} v #{escape(away)} |"
        end

      <<~TABLE.strip
        | | |
        | --- | --- |
        #{rows.join("\n")}
      TABLE
    end

    # API-Football flags the winner per side, which saves inferring it
    # from goals and gets draws right without special-casing.
    #
    # Which side is "us" is decided by team id, never by name. The
    # configured label is a display string chosen by the admin
    # ("Femenino") and generally won't resemble the API's own name
    # ("Sevilla FC W"), so matching on it silently produced blank
    # outcomes.
    def outcome(fixture, team_id)
      ours = which_side(fixture, team_id)
      return "" if ours.nil?

      winner = fixture.dig("teams", ours, "winner")
      return "Draw" if winner.nil? && FINISHED.include?(status(fixture))

      winner ? "**Win**" : "Loss"
    end

    def which_side(fixture, team_id)
      return nil if team_id.nil?

      return "home" if fixture.dig("teams", "home", "id").to_i == team_id.to_i
      return "away" if fixture.dig("teams", "away", "id").to_i == team_id.to_i

      nil
    end

    def short_date(fixture)
      time = parse(fixture.dig("fixture", "date"))
      return "" if time.nil?

      time.in_time_zone(@timezone).strftime("%-d %b")
    rescue StandardError
      ""
    end

    def kickoff(fixture)
      time = parse(fixture.dig("fixture", "date"))
      return "TBC" if time.nil?

      local = time.in_time_zone(@timezone)
      "#{local.strftime("%a %-d %b, %-I:%M %p")}"
    rescue StandardError
      "TBC"
    end

    def parse(value)
      return nil if value.nil? || value.to_s.empty?

      Time.parse(value.to_s).utc
    rescue ArgumentError, TypeError
      nil
    end

    def escape(text)
      text.to_s.gsub("|", "\\|")
    end
  end
end
