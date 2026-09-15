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
      # value is read back in, so a Number answering `"42"` is not ruled out. A
      # value that is not already of its column's type is therefore converted --
      # the in-memory pass of the primary-key short-circuit would otherwise drop
      # a row on `"42" == 42.0`, comparing a read string with the float
      # `ConditionTreeParser.cast_to_type` casts the filter to.
      #
      # A date stays the string it is: the filter carries an ISO8601 string too,
      # and comparing two of those is the ordering itself.
      def coerce_custom_field(value, column_type)
        return nil if value.nil?

        case column_type
        when 'Number'  then coerce_number(value)
        when 'Boolean' then coerce_boolean(value)
        else                value
        end
      end

      # A value already numeric is handed back untouched: `ConditionTreeLeaf#match`
      # compares with `==` and `Array#include?`, both of which hold across Integer
      # and Float, so nothing needs widening -- and widening would make an integer
      # field display the `12.0` it does not hold, where `FilterValue#format_float`
      # narrows the very same value on the way out. A string is read to the
      # tightest form for that reason, the two halves agreeing on what an integer
      # looks like.
      #
      # A number that cannot be read reads as absent rather than as zero.
      #
      # Integers are parsed as integers rather than reached through a Float: past
      # 2**53 the intermediate loses the last digits, and `"9007199254740993"`
      # would be both displayed and compared as ...992. Base 10 is passed
      # explicitly -- `Integer("012")` is 10, Ruby reading a leading zero as
      # octal, which would silently renumber every zero-padded value Pylon holds.
      def coerce_number(value)
        return value if value.is_a?(Numeric)

        integer = Integer(value, 10, exception: false)
        return integer unless integer.nil?

        float = Float(value, exception: false)
        return nil if float.nil?

        float == float.to_i ? float.to_i : float
      end

      # An empty boolean reads as absent as well: `false` is an answer of its own,
      # and Pylon gave none.
      def coerce_boolean(value)
        return value if [true, false].include?(value)
        return nil if value.to_s.strip.empty?

        !%w[false 0 no].include?(value.to_s.strip.downcase)
      end
    end
  end
end
