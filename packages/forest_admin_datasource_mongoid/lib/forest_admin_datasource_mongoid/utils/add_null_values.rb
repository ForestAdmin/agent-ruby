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
        add_null_values_on_tree(record, projection_tree(projection))
      end

      def add_null_values(records, projection)
        tree = projection_tree(projection)
        records.filter_map { |record| add_null_values_on_tree(record, tree) }
      end

      private

      def projection_tree(projection)
        ForestAdminDatasourceToolkit::Components::Query::ProjectionTree.build(
          ForestAdminDatasourceToolkit::Components::Query::Projection.new(projection)
        )
      end

      def add_null_values_on_tree(record, tree)
        return nil if record.nil?

        result = record.dup

        tree.columns.each { |column| result[column] ||= nil }

        tree.relations.each do |relation, sub_tree|
          value = result[relation]

          if value.is_a?(Array)
            result[relation] = value.map { |child_record| add_null_values_on_tree(child_record, sub_tree) }
          elsif value.is_a?(Hash)
            result[relation] = add_null_values_on_tree(value, sub_tree)
          else
            result[relation] ||= nil
          end
        end

        remove_not_exist_record(result)
      end
    end
  end
end
