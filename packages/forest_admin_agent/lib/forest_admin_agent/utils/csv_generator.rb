require 'csv'

module ForestAdminAgent
  module Utils
    class CsvGenerator
      # Labels are positionally aligned with the requested projection, so dropping a field without
      # dropping its label shifts every later value under the wrong heading.
      # The header carries one label per exported column, so a label survives exactly when the
      # projection path at its index did. A count that does not match the projection cannot be mapped
      # onto columns — a to-one relation expanded into several paths, or a polymorphic type field
      # appended — so the header is handed back untouched and the stream falls back to field paths.
      def self.filter_header(header, requested, kept)
        return header if header.nil? || kept.size == requested.size

        labels = parse_header_labels(header)

        return header unless labels&.size == requested.size

        labels.each_with_index
              .select { |_label, index| kept.include?(requested[index]) }
              .map(&:first)
      end

      # The front joins the labels with commas; a JSON array comes from older callers.
      def self.parse_header_labels(header)
        return header if header.is_a?(Array)
        return nil unless header.is_a?(String)

        parsed = begin
          JSON.parse(header)
        rescue JSON::ParserError
          nil
        end

        parsed.is_a?(Array) ? parsed : header.split(',', -1)
      end

      def self.generate(records, projection)
        data = {}
        projection.each do |schema_field|
          is_relation = schema_field.include?(':') && projection.relations.key?(schema_field.split(':').first)
          col_name = (is_relation ? schema_field.split(':').first : schema_field)

          data[col_name] = []
          records.each do |row|
            data[col_name] << if is_relation
                                row[col_name]&.[](schema_field.split(':').last)
                              else
                                row[col_name]
                              end
          end
        end

        generate_csv_string(data)
      end

      # data = {
      #   "id" => [1, 2],
      #   "email" => ["mv@test.com", "na@test.com"],
      #   "name" => ["Matthieu", "Nicolas"],
      # }
      def self.generate_csv_string(data)
        CSV.generate do |csv|
          # headers
          csv << data.keys

          num_rows = data.values.first.size
          num_rows.times do |i|
            row = data.keys.map { |key| data[key][i] }
            csv << row
          end
        end
      end
    end
  end
end
