# frozen_string_literal: true

require 'csv'

module ForestAdminAgent
  module Utils
    class CsvGeneratorStream
      CHUNK_SIZE = 1000

      # @param header [Array<String>] CSV header fields
      # @param filter [ForestAdminDatasourceToolkit::Components::Query::Filter] Query filter
      # @param projection [ForestAdminDatasourceToolkit::Components::Query::Projection] Fields to include
      # @param list_records [Proc] A callable that fetches records: ->(batch_filter) { ... }
      # @param limit_export_size [Integer, nil] Maximum number of records to export
      # @return [Enumerator] Lazy enumerator that yields CSV rows
      def self.stream(header, filter, projection, list_records, limit_export_size = nil)
        Enumerator.new do |yielder|
          # Yield header row first (client receives immediately)
          # Escaped like any other row: the labels are the caller's, and one carrying a comma or a
          # quote would otherwise emit a header row wider than the data under it.
          yielder << CSV.generate_line(parse_header(header, projection))

          offset = 0

          loop do
            # Fetch batch of records
            batch_filter = filter.override(
              page: ForestAdminDatasourceToolkit::Components::Query::Page.new(offset: offset, limit: CHUNK_SIZE)
            )
            records = list_records.call(batch_filter)

            # Break if no more records
            break if records.empty?

            # Convert each record to CSV row and yield immediately
            records.each do |record|
              yielder << generate_row(record, projection)
            end

            # Update offset
            offset += CHUNK_SIZE

            # Check if we've reached the export limit
            break if limit_export_size && offset >= limit_export_size

            # Check if this was a partial batch (last batch)
            break if records.length < CHUNK_SIZE

            # Periodic garbage collection to prevent memory creep
            GC.start(full_mark: false) if (offset % 10_000).zero?
          end
        rescue IOError, Errno::EPIPE => e
          # Client disconnected - clean up gracefully
          Facades::Container.logger&.log(
            'Info',
            "CSV export interrupted at offset #{offset}: #{e.message}"
          )
        end
      end

      # Parse header parameter into an array
      # @param header [String, Array, nil] Header as a comma-joined string, JSON array, array or nil
      # @param projection [Projection] Field projection
      # @return [Array<String>] The labels when there is exactly one per exported column, the field
      #   paths otherwise — a header that cannot be mapped onto the columns would mislabel them
      def self.parse_header(header, projection)
        labels = CsvGenerator.parse_header_labels(header)

        labels&.size == projection.size ? labels : projection.to_a
      end

      # Generate CSV row from record data
      # @param record [Hash] Record data
      # @param projection [Projection] Field projection
      # @return [String] CSV data line
      def self.generate_row(record, projection)
        values = projection.map do |field|
          value = ForestAdminDatasourceToolkit::Utils::Record.field_value(record, field)
          format_value(value)
        end
        CSV.generate_line(values)
      end

      # Format individual value for CSV output
      # @param value [Object] Value to format
      # @return [String] Formatted value
      def self.format_value(value)
        case value
        when nil
          ''
        when Array, Hash
          value.to_json
        when Date, DateTime, Time
          value.respond_to?(:iso8601) ? value.iso8601 : value.to_s
        else
          value.to_s
        end
      end

      private_class_method :parse_header, :generate_row, :format_value
    end
  end
end
