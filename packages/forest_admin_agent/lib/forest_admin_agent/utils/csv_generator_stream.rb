# frozen_string_literal: true

require 'csv'

module ForestAdminAgent
  module Utils
    class CsvGeneratorStream
      CHUNK_SIZE = 1000

      # @param collection [ForestAdminDatasourceToolkit::Collection] The collection to export
      # @param caller [ForestAdminDatasourceToolkit::Components::Caller] The authenticated caller
      # @param filter [ForestAdminDatasourceToolkit::Components::Query::Filter] Query filter
      # @param projection [ForestAdminDatasourceToolkit::Components::Query::Projection] Fields to include
      # @param limit_export_size [Integer, nil] Maximum number of records to export
      # @return [Enumerator] Lazy enumerator that yields CSV rows
      def self.stream(collection, caller, filter, projection, limit_export_size = nil)
        Enumerator.new do |yielder|
          # Yield header row first (client receives immediately)
          yielder << generate_header(projection)

          offset = 0

          loop do
            # Fetch batch of records
            batch_filter = filter.override(
              page: ForestAdminDatasourceToolkit::Components::Query::Page.new(offset: offset, limit: CHUNK_SIZE)
            )
            records = collection.list(caller, batch_filter, projection)

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

      # Generate CSV header row from projection
      # @param projection [Projection] Field projection
      # @return [String] CSV header line
      def self.generate_header(projection)
        headers = projection.map do |field|
          # Handle relation fields (e.g., "user:name" -> "user")
          if field.include?(':')
            "#{field.split(":").first}:#{field.split(":").last}"
          else
            field.to_s
          end
        end
        CSV.generate_line(headers)
      end

      # Generate CSV row from record data
      # @param record [Hash] Record data
      # @param projection [Projection] Field projection
      # @return [String] CSV data line
      def self.generate_row(record, projection)
        values = projection.map do |field|
          value = if field.include?(':')
                    # Handle relation fields
                    relation_name = field.split(':').first
                    relation_field = field.split(':').last
                    record[relation_name]&.[](relation_field)
                  else
                    record[field]
                  end
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
        when Date, DateTime, Time
          value.respond_to?(:iso8601) ? value.iso8601 : value.to_s
        when TrueClass, FalseClass
          value.to_s
        when Array, Hash
          # Serialize complex types as JSON, truncate if too large
          json = value.to_json
          json.length > 10_000 ? "#{json[0...10_000]}..." : json
        when String
          # Truncate very long strings
          value.length > 10_000 ? "#{value[0...10_000]}..." : value
        end
      end

      private_class_method :generate_header, :generate_row, :format_value
    end
  end
end
