require 'json'

module ForestAdminAuditTrail
  module Stores
    # Default store used when none is configured: it only logs each change. Write-only — the
    # record-history route reading from it always gets an empty result.
    class LogStore
      def initialize(logger: nil)
        @logger = logger
      end

      def append(record)
        message = "[audit-trail] #{record.to_h.to_json}"
        @logger ? @logger.log('Info', message) : warn(message)
      end

      def list_by_record(**)
        []
      end

      def count_by_record(**)
        0
      end

      def list_by_correlation(**)
        []
      end

      def list_by_correlations(**)
        []
      end
    end
  end
end
