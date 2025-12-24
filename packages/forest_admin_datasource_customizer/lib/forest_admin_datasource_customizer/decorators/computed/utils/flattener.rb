module ForestAdminDatasourceCustomizer
  module Decorators
    module Computed
      module Utils
        class Flattener
          include ForestAdminDatasourceToolkit::Components::Query

          class Undefined
            def key?(_key)
              false
            end

            def dig(*_keys)
              self
            end
          end

          MARKER_NAME = '__null_marker'.freeze
          def self.with_null_marker(projection)
            seen = Set.new(projection)
            new_projection = Projection.new(projection)

            projection.each do |path|
              parts = path.split(':')

              parts.slice(1, parts.size).each_with_index do |_item, index|
                marker = "#{parts.slice(0, index + 1).join(":")}:#{MARKER_NAME}"
                next if seen.include?(marker)

                seen << marker
                new_projection << marker
              end
            end

            new_projection
          end

          def self.flatten(records, projection)
            projection.map do |field|
              # because we don't compute computed fields over polymorphic relation (only usage of *),
              # we decide to consider the all record as a value instead of a relation
              parts = field.split(':').reject { |part| part == '*' }

              records.map do |record|
                value = record

                parts.slice(0, parts.size - 1).each_with_index do |_item, index|
                  value = if value&.key?(parts[index])
                            value[parts[index]]
                          else
                            Undefined.new
                          end
                end

                # for markers, the value tells us which fields are null so that we can set them.
                if parts[parts.length - 1] == MARKER_NAME
                  value.nil? ? nil : Undefined.new
                elsif value&.key?(parts[parts.length - 1])
                  value[parts[parts.length - 1]]
                else
                  Undefined.new
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
                parts = path.split(':').reject { |part| [MARKER_NAME, '*'].include?(part) }
                value = flatten[path_index][record_index]

                # Ignore undefined values.
                next if value.is_a? Undefined

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
