module ForestAdminAgent
  module Utils
    class Id
      include ForestAdminDatasourceToolkit::Utils
      def self.unpack_id(collection, packed_id, with_key: false)
        primary_keys = ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(collection)
        primary_key_values = packed_id.split('|')
        if (nb_pks = primary_keys.size) != (nb_values = primary_key_values.size)
          raise Exceptions::ForestException, "Expected $primaryKeyNames a size of #{nb_pks} values, found #{nb_values}"
        end

        result = primary_keys.map.with_index do |pk_name, index|
          field = collection.fields[pk_name]
          value = primary_key_values[index]
          casted_value = field.column_type == 'Number' ? value.to_i : value
          # TODO: call FieldValidator::validateValue($value, $field, $castedValue);

          [pk_name, casted_value]
        end.to_h

        with_key ? result : result.values
      end
    end
  end
end
