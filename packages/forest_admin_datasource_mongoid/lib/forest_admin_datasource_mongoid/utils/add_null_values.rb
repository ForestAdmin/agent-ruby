module ForestAdminDatasourceMongoid
  module Utils
    module AddNullValues
      # Filter out records that have been tagged as not existing
      # If the key FOREST_RECORD_DOES_NOT_EXIST is present in the record, the record is removed
      # If a nested object has a key with FOREST_RECORD_DOES_NOT_EXIST, the nested object is removed
      def remove_not_exist_record(record)
        return nil if record.nil? || record[Pipeline::ConditionGenerator::FOREST_RECORD_DOES_NOT_EXIST]

        record.transform_values! do |value|
          if value.is_a?(Hash) && value[Pipeline::ConditionGenerator::FOREST_RECORD_DOES_NOT_EXIST]
            nil
          else
            value
          end
        end

        record
      end

      def add_null_values_on_record(record, projection)
        return nil if record.nil?

        fill_null_values(record, build_null_values_tree(projection))
      end

      def add_null_values(records, projection)
        return [] if records.empty?

        tree = build_null_values_tree(projection)
        records.filter_map { |record| fill_null_values(record, tree) }
      end

      private

      def build_null_values_tree(paths)
        paths.group_by { |path| path.split(':', 2).first }.to_h do |key, key_paths|
          child_paths = key_paths.filter_map { |path| path.split(':', 2)[1] }
          [key, child_paths.empty? ? nil : build_null_values_tree(child_paths)]
        end
      end

      def fill_null_values(record, tree)
        return nil if record.nil?

        result = record.dup

        tree.each do |key, sub_tree|
          result[key] ||= nil
          result[key] = fill_nested_null_values(result[key], sub_tree) if sub_tree
        end

        remove_not_exist_record(result)
      end

      def fill_nested_null_values(value, sub_tree)
        case value
        when Array then value.map { |item| item.is_a?(Hash) ? fill_null_values(item, sub_tree) : item }
        when Hash then fill_null_values(value, sub_tree)
        else value
        end
      end
    end
  end
end
