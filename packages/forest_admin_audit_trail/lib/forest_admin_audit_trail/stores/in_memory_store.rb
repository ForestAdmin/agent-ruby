require 'time'

module ForestAdminAuditTrail
  module Stores
    # Read/write store kept in memory. Handy for tests and for exercising the record-history route
    # without a database.
    class InMemoryStore
      def initialize
        @records = []
      end

      def append(record)
        @records << record
      end

      def list_by_record(collection:, record_id:, skip: 0, limit: nil,
                         user_ids: nil, start_timestamp: nil, end_timestamp: nil, order: 'asc')
        matches = sorted(matching(collection, record_id, user_ids, start_timestamp, end_timestamp), order)

        skip ||= 0
        ending = limit.nil? ? matches.length : skip + limit
        matches[skip...ending] || []
      end

      def count_by_record(collection:, record_id:, user_ids: nil, start_timestamp: nil, end_timestamp: nil)
        matching(collection, record_id, user_ids, start_timestamp, end_timestamp).length
      end

      private

      def matching(collection, record_id, user_ids, start_timestamp, end_timestamp)
        @records.select do |record|
          record.collection == collection && record.record_id == record_id &&
            (user_ids.nil? || user_ids.include?(record.user_id)) &&
            (start_timestamp.nil? || as_time(record.timestamp) >= as_time(start_timestamp)) &&
            (end_timestamp.nil? || as_time(record.timestamp) <= as_time(end_timestamp))
        end
      end

      # Ties on equal timestamps fall back to append order (index) in both directions — the in-memory
      # equivalent of the SQL store's auto-increment id tie-break.
      def sorted(records, order)
        sign = order.to_s == 'desc' ? -1 : 1
        records.each_with_index.sort_by { |record, i| [sign * as_time(record.timestamp).to_f, i] }.map(&:first)
      end

      def as_time(value)
        value.is_a?(::Time) ? value : ::Time.iso8601(value.to_s)
      end
    end
  end
end
