# frozen_string_literal: true

module ::ClubTeams
  module Providers
    # Every provider answers the same question — "what has this team
    # played and what is it about to play?" — and returns ClubTeams
    # ::Fixture objects.
    #
    # Failure is reported two ways on purpose: a nil return says "I have
    # nothing", and last_error says why in words. The caller needs both,
    # because an empty season and a rejected API key look identical
    # otherwise, and only one of them should overwrite a good post.
    class Base
      attr_reader :last_error

      # @return [Array<ClubTeams::Fixture>, nil]
      def fixtures(team_id:, leagues: [], back_days: 150, forward_days: 90)
        raise NotImplementedError
      end

      # Human-readable name for logs and the probe script.
      def self.provider_name
        name.split("::").last.downcase
      end

      # True when the provider needs an API key configured.
      def self.needs_key?
        true
      end

      private

      def fail!(message)
        @last_error = message
        Rails.logger.warn("[#{::ClubTeams::PLUGIN_NAME}] #{self.class.provider_name}: #{message}") if defined?(Rails)
        nil
      end
    end
  end
end
