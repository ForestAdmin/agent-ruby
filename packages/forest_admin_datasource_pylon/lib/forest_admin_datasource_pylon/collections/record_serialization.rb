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
          record[cf[:column_name]] = coerce_custom_field(custom_field_value(entry), cf[:schema].column_type)
        end
      end

      # Pylon spells a custom field as `slug => {"slug": ..., "value": ...}`,
      # with `"values": [...]` instead of `"value"` for multi-value fields.
      def custom_field_value(entry)
        return entry unless entry.is_a?(Hash)

        entry.key?('value') ? entry['value'] : entry['values']
      end

      # The API reference documents what a custom field *is*, never the form its
      # value is read back in, so a Number answering `"42"` is not ruled out. The
      # value therefore takes the form the agent gives a filter value of the same
      # type -- `ConditionTreeParser.cast_to_type` casts a Number with `to_f` and
      # a Boolean into a real boolean -- so the in-memory pass of the primary-key
      # short-circuit compares two comparable values whichever form came back,
      # rather than dropping the row on `"42" == 42.0`.
      #
      # A date stays the string it is: the filter carries an ISO8601 string too,
      # and comparing two of those is the ordering itself.
      def coerce_custom_field(value, column_type)
        return nil if value.nil?

        case column_type
        when 'Number'  then Float(value, exception: false)
        when 'Boolean' then coerce_boolean(value)
        else                value
        end
      end

      # A number that cannot be read reads as absent rather than as zero, and so
      # does an empty boolean: `false` is an answer, and Pylon gave none.
      def coerce_boolean(value)
        return value if [true, false].include?(value)
        return nil if value.to_s.strip.empty?

        !%w[false 0 no].include?(value.to_s.strip.downcase)
      end
    end
  end
end
