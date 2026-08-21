require 'csv'

module ForestAdminAgent
  module Utils
    class CsvGenerator
      # Labels are positionally aligned with the requested projection, so dropping a field without
      # dropping its label shifts every later value under the wrong heading.
      def self.filter_header(header, requested, kept)
        return header if header.nil? || kept.size == requested.size

        labels = header.is_a?(String) ? parse_header_labels(header) : header

        return header unless labels.is_a?(Array)

        labels.each_with_index
              .select { |_label, index| kept.include?(requested[index]) }
              .map(&:first)
      end

      def self.parse_header_labels(header)
        JSON.parse(header)
      rescue JSON::ParserError
        nil
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
