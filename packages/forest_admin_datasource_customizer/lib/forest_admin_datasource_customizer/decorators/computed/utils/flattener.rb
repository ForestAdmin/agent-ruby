module ForestAdminDatasourceCustomizer
  module Decorators
    module Computed
      module Utils
        class Flattener
          def self.flatten(records, projection)
            projection.map do |field|
              records.map { |record| ForestAdminDatasourceToolkit::Utils::Record.field_value(record, field) }
            end
          end

          def self.un_flatten(flatten, projection)
            num_records = flatten[0]&.length || 0
            records = []

            (0...num_records).each do |record_index|
              records[record_index] = {}

              projection.each_with_index do |path, path_index|
                parts = path.split(':').reject { |part| part.nil? || part.empty? }
                value = flatten[path_index][record_index]

                # Ignore undefined values.
                next if value.nil?

                # Set all others (including null)
                record = records[record_index]

                (0...parts.length).each do |part_index|
                  part = parts[part_index]

                  if part_index == parts.length - 1
                    record[part] = value
                  elsif record[part].nil?
                    record[part] = {}
                  end

                  record = record[part]
                end
              end
            end

            records
          end
        end
      end
    end
  end
end
