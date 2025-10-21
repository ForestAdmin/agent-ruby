module ForestAdminAgent
  module Utils
    class Id
      include ForestAdminDatasourceToolkit::Utils
      include ForestAdminDatasourceToolkit

      def self.pack_ids(schema, records)
        records.map { |packed_id| pack_id(schema, packed_id) }
      end

      def self.pack_id(schema, record)
        pk_names = ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(schema)

        raise Exceptions::ForestException, 'This collection has no primary key' if pk_names.empty?

        pk_names.map { |pk| record[pk].to_s }.join('|')
      end

      def self.unpack_id(collection, packed_id, with_key: false)
        primary_keys = ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(collection)
        primary_key_values = packed_id.to_s.split('|')
        if (nb_pks = primary_keys.size) != (nb_values = primary_key_values.size)
          raise Exceptions::ForestException, "Expected #{nb_pks} primary keys, found #{nb_values}"
        end

        result = primary_keys.map.with_index do |pk_name, index|
          field = collection.schema[:fields][pk_name]
          value = primary_key_values[index]
          casted_value = field.column_type == 'Number' ? value.to_i : value
          ForestAdminDatasourceToolkit::Validations::FieldValidator.validate_value(pk_name, field, casted_value)

          [pk_name, casted_value]
        end.to_h

        with_key ? result : result.values
      end

      def self.unpack_ids(collection, packed_ids, with_key: false)
        packed_ids.map { |item| unpack_id(collection, item, with_key: with_key) }
      end

      def self.parse_selection_ids(collection, params, with_key: false)
        attributes = begin
          params.dig(:data, :attributes)
        rescue StandardError
          nil
        end

        are_excluded = attributes&.key?(:all_records) ? attributes[:all_records] : false
        input_ids = attributes&.key?(:ids) ? attributes[:ids] : params[:data].map { |item| item['id'] }
        ids = unpack_ids(
          collection,
          are_excluded ? attributes[:all_records_ids_excluded] : input_ids,
          with_key: with_key
        )

        { are_excluded: are_excluded, ids: ids }
      end
    end
  end
end
