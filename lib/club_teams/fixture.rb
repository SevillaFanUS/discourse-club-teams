# frozen_string_literal: true

module ::ClubTeams
  # One match, normalised away from whichever API produced it.
  #
  # Providers differ in almost every detail — status vocabulary, score
  # types, how a draw is signalled — so they each translate into this
  # and nothing downstream has to care where the data came from.
  class Fixture
    STATES = %i[scheduled live finished postponed cancelled unknown].freeze

    attr_reader :kickoff,
                :state,
                :home_id,
                :home_name,
                :home_score,
                :away_id,
                :away_name,
                :away_score,
                :competition,
                :url

    def initialize(
      kickoff:,
      state:,
      home_id:,
      home_name:,
      away_id:,
      away_name:,
      home_score: nil,
      away_score: nil,
      competition: nil,
      url: nil
    )
      @kickoff = kickoff
      @state = STATES.include?(state) ? state : :unknown
      @home_id = home_id.to_s
      @home_name = home_name.to_s
      @home_score = home_score
      @away_id = away_id.to_s
      @away_name = away_name.to_s
      @away_score = away_score
      @competition = competition
      @url = url
    end

    def played?
      state == :finished
    end

    def called_off?
      state == :postponed || state == :cancelled
    end

    def scored?
      !home_score.nil? && !away_score.nil?
    end

    def score_line
      scored? ? "#{home_score}–#{away_score}" : "—"
    end

    # "home", "away", or nil when this fixture doesn't involve the team.
    #
    # Matched on id, never on name: the label an admin picks ("Femenino")
    # rarely resembles the API's own name ("Sevilla FC W"), and matching
    # on names silently produced blank results the first time round.
    def side_for(team_id)
      return nil if team_id.nil?

      wanted = team_id.to_s
      return "home" if home_id == wanted
      return "away" if away_id == wanted

      nil
    end

    # "Win" / "Loss" / "Draw" for the given team, or nil if the match
    # isn't finished or isn't theirs.
    def outcome_for(team_id)
      return nil unless played?

      side = side_for(team_id)
      return nil if side.nil?
      return nil unless scored?

      ours = side == "home" ? home_score : away_score
      theirs = side == "home" ? away_score : home_score

      return "Draw" if ours == theirs

      ours > theirs ? "Win" : "Loss"
    end

    def opponent_for(team_id)
      case side_for(team_id)
      when "home" then away_name
      when "away" then home_name
      end
    end
  end
end
