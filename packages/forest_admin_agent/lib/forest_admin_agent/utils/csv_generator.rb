module ForestAdminAgent
  module Utils
    class CsvGenerator
      def self.generate(records, projection)
        data = {}
        projection.each do |schema_field|
          is_relation = schema_field.include?(':') && projection.relations.key?(schema_field.split(':').first)
          col_name = (is_relation ? schema_field.split(':').first : schema_field)

          data[col_name] = []
          records.each do |row|
            data[col_name] << if is_relation
                                row[col_name][schema_field.split(':').last]
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
