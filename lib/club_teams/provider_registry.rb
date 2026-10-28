# frozen_string_literal: true

module ::ClubTeams
  # Maps the provider name in a team spec to an instance.
  #
  # Providers are built per sync run, not memoised, because each holds
  # the error state of its last call.
  module ProviderRegistry
    KNOWN = {
      "espn" => ::ClubTeams::Providers::Espn,
      "api_football" => ::ClubTeams::Providers::ApiFootball,
    }.freeze

    def self.names
      KNOWN.keys
    end

    def self.known?(name)
      KNOWN.key?(name.to_s)
    end

    def self.build(name, api_key: nil)
      klass = KNOWN[name.to_s]
      return nil if klass.nil?

      klass.needs_key? ? klass.new(api_key) : klass.new
    end
  end
end
