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
            num_records = flatten[0].length || 0
            records = Array.new(num_records) { [] }
            projection.columns.each_with_index do |field, index|
              flatten[index].each_with_index do |value, key|
                records[key] = {} if records[key].empty?
                records[key][field] = value || nil
              end
            end

            projection.relations.each do |relation, paths|
              sub_flatten = []
              paths.each do |path|
                sub_flatten << flatten[projection.search("#{relation}:#{path}")]
              end

              sub_records = un_flatten(sub_flatten, paths)
              records.each_key do |key|
                records[key][relation] = sub_records[key]
              end
            end

            records.map do |record|
              record.any? { |value| !value.nil? } ? record : nil
            end
          end
        end
      end
    end
  end
end
