module ForestAdminDatasourceCustomizer
  module Decorators
    module Computed
      module Utils
        class Flattener
          include ForestAdminDatasourceToolkit::Components::Query

          MARKER_NAME = '__null_marker'.freeze
          def self.with_null_marker(projection)
            new_projection = Projection.new(projection)
            projection.each do |path|
              parts = path.split(':')

              parts.slice(1, parts.size).each_with_index do |_item, index|
                new_projection << "#{parts.slice(0, index + 1).join(":")}:#{MARKER_NAME}"
              end
            end

            new_projection.uniq
          end

          def self.flatten(records, projection)
            projection.map do |field|
              parts = field.split(':')
              records.map do |record|
                value = record

                parts.slice(0, parts.size - 1).each_with_index { |_item, index| value = value[parts[index]] }

                # for markers, the value tells us which fields are null so that we can set them.
                if parts[parts.length - 1] == MARKER_NAME
                  value.nil? ? nil : 'undefined'
                else
                  value&.dig(parts[parts.length - 1])
                end
              end
            end
          end

          def self.un_flatten(flatten, projection)
            num_records = flatten[0]&.length || 0
            records = []

            (0...num_records).each do |record_index|
              records[record_index] = {}

              projection.each_with_index do |path, path_index|
                parts = path.split(':').reject { |part| part == MARKER_NAME }
                value = flatten[path_index][record_index]

                # Ignore undefined values.
                next if value == 'undefined'

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
