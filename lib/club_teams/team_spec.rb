# frozen_string_literal: true

module ::ClubTeams
  # Parses the club_teams_teams setting into something the sync job can
  # act on.
  #
  # Preferred form, pipe-separated, one team per comma:
  #
  #   Femenino|espn|21424|esp.w.1;esp.copa_de_la_reina
  #   Sevilla Atletico|api_football|5678
  #
  # Legacy form from v0.1, still accepted so an existing setting keeps
  # working after upgrade:
  #
  #   Femenino:1234, Sevilla Atletico:5678
  class TeamSpec
    DEFAULT_PROVIDER = "api_football"

    attr_reader :label, :provider, :id, :leagues

    def initialize(label:, provider:, id:, leagues: [])
      @label = label
      @provider = provider
      @id = id
      @leagues = leagues
    end

    def self.parse_all(raw)
      raw.to_s.split(",").filter_map { |entry| parse(entry) }
    end

    def self.parse(entry)
      text = entry.to_s.strip
      return nil if text.empty?

      text.include?("|") ? parse_piped(text) : parse_legacy(text)
    end

    def self.parse_piped(text)
      label, provider, id, leagues = text.split("|", 4).map { |part| part.to_s.strip }

      return nil if label.to_s.empty? || id.to_s.empty?

      new(
        label: label,
        provider: provider.to_s.empty? ? DEFAULT_PROVIDER : provider,
        id: id,
        leagues: leagues.to_s.split(";").map(&:strip).reject(&:empty?),
      )
    end

    # Split on the LAST colon: a label may legitimately contain one
    # ("Femenino: Liga F"), but the id is always the trailing segment.
    def self.parse_legacy(text)
      index = text.rindex(":")
      return nil if index.nil?

      label = text[0...index].strip
      id = text[(index + 1)..].to_s.strip

      return nil if label.empty? || id.empty?

      new(label: label, provider: DEFAULT_PROVIDER, id: id, leagues: [])
    end

    def to_s
      "#{label} (#{provider}##{id}#{leagues.any? ? " in #{leagues.join(", ")}" : ""})"
    end
  end
end
