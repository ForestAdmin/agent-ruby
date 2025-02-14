module ForestAdminDatasourceMongoid
  module Utils
    module AddNullValues
      # Filter out records that have been tagged as not existing
      # If the key FOREST_RECORD_DOES_NOT_EXIST is present in the record, the record is removed
      # If a nested object has a key with FOREST_RECORD_DOES_NOT_EXIST, the nested object is removed
      # rubocop:disable Style/ConditionalAssignment
      def remove_not_exist_record(record)
        return nil if record.nil? || record[Pipeline::ConditionGenerator::FOREST_RECORD_DOES_NOT_EXIST]

        record.each do |key, value|
          if value.is_a?(Hash) && value.value?(Pipeline::ConditionGenerator::FOREST_RECORD_DOES_NOT_EXIST)
            record[key] = nil
          else
            # TODO : TEST PROPERLY - Récursion pour les sous-objets
            record[key] = remove_not_exist_record(value)
          end
        end

        record
      end
      # rubocop:enable Style/ConditionalAssignment

      def add_null_values_on_record(record, projection)
        return nil if record.nil?

        result = record.dup

        projection.each do |field|
          field_prefix = field.split(':').first
          result[field_prefix] ||= nil
        end

        nested_prefixes = projection.select { |field| field.include?(':') }.map { |field| field.split(':').first }.uniq

        nested_prefixes.each do |nested_prefix|
          child_paths = projection.filter { |field| field.start_with?("#{nested_prefix}:") }
                                  .map { |field| field[nested_prefix.size + 1..] }

          next unless result[nested_prefix] && !result[nested_prefix].nil?

          if result[nested_prefix].is_a?(Array)
            result[nested_prefix] = result[nested_prefix].map do |child_record|
              add_null_values_on_record(child_record, child_paths)
            end
          elsif result[nested_prefix].is_a?(Hash)
            result[nested_prefix] = add_null_values_on_record(result[nested_prefix], child_paths)
          end
        end

        remove_not_exist_record(result)
      end

      def add_null_values(records, projection)
        records.filter_map { |record| add_null_values_on_record(record, projection) }
      end
    end
  end
end
