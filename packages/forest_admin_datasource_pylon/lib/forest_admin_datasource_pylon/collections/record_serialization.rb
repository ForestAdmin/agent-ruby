module ForestAdminDatasourcePylon
  module Collections
    # The two parts of a Pylon payload every collection reads the same way: the
    # nested `{ id: ... }` objects it flattens into foreign-key columns, and the
    # custom fields the organization defined, which are columns of their own.
    module RecordSerialization
      private

      def nested_id(value)
        value['id'] if value.is_a?(Hash)
      end

      def add_custom_field_values(record, values)
        custom_fields.each do |cf|
          entry = values.is_a?(Hash) ? values[cf[:column_name]] : nil
          record[cf[:column_name]] = custom_field_value(entry)
        end
      end

      # Pylon spells a custom field as `slug => {"slug": ..., "value": ...}`,
      # with `"values": [...]` instead of `"value"` for multi-value fields.
      def custom_field_value(entry)
        return entry unless entry.is_a?(Hash)

        entry.key?('value') ? entry['value'] : entry['values']
      end
    end
  end
end
