require 'base64'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Binary
      class BinaryCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit
        include ForestAdminDatasourceToolkit::Decorators
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

        def initialize(child_collection, datasource)
          super
          @use_hex_conversion = {}
        end

        def set_binary_mode(name, type)
          field = @child_collection.schema[:fields][name]

          raise Exceptions::ForestException, 'Invalid binary mode' unless %w[datauri hex].include?(type)

          unless field.type == 'Column' && field.column_type == 'Binary'
            raise Exceptions::ForestException, 'Expected a binary field'
          end

          @use_hex_conversion[name] = (type == 'hex')
          mark_schema_as_dirty
        end

        def refine_schema(sub_schema)
          fields = {}

          sub_schema[:fields].each do |name, schema|
            if schema.type == 'Column'
              new_schema = schema.dup
              new_schema.column_type = replace_column_type(schema.column_type)
              new_schema.validations = replace_validation(name, schema)
              fields[name] = new_schema
            else
              fields[name] = schema
            end
          end

          sub_schema[:fields] = fields
          sub_schema
        end

        def create(caller, data)
          data_with_binary = convert_record(true, data)
          record = super(caller, data_with_binary)

          convert_record(false, record)
        end

        def list(caller, filter, projection)
          records = super(caller, filter, projection)
          records.map! { |record| convert_record(false, record) }

          records
        end

        def update(caller, filter, patch)
          super(caller, filter, convert_record(true, patch))
        end

        def aggregate(caller, filter, aggregation, limit = nil)
          rows = super
          rows.map! do |row|
            [
              value: row[:value],
              group: row[:group].map! { |path, value| convert_value(false, path, value) }
            ]
          end
        end

        private

        def should_use_hex(name)
          @use_hex_conversion[name] if @use_hex_conversion.key?(name)

          Utils::Schema.primary_key?(@child_collection, name) || Utils::Schema.foreign_key?(@child_collection, name)
        end

        def convert_record(to_backend, record)
          if record
            record = record.to_h do |path, value|
              [path, convert_value(to_backend, path, value)]
            end
          end

          record
        end

        def convert_value(to_backend, path, value)
          prefix, suffix = path.split(':')
          field = @child_collection.schema[:fields][prefix]

          if field.type != 'Column'
            foreign_collection = @datasource.get_collection(field.foreign_collection)

            return suffix ? foreign_collection.convert_value(to_backend, suffix,
                                                             value) : foreign_collection.convert_record(to_backend,
                                                                                                        value)
          end

          binary_mode = should_use_hex(path)

          convert_value_helper(to_backend, field.column_type, binary_mode, value)
        end

        def convert_value_helper(to_backend, column_type, use_hex, value)
          if value
            return convert_scalar(to_backend, use_hex, value) if column_type == 'Binary'

            if column_type.is_a? Array
              return value.map { |v| convert_value_helper(to_backend, column_type[0], use_hex, v) }
            end

            unless column_type.is_a? String
              return column_type.to_h { |key, type| [key, convert_value_helper(to_backend, type, use_hex, value[key])] }
            end
          end

          value
        end

        def convert_scalar(to_backend, use_hex, value)
          if to_backend
            return use_hex ? hex_to_bin(value) : Base64.decode64(value.partition(',')[1])
          end

          return bin_to_hex(value) if use_hex

          data = Base64.encode64(value)
          mime = detect_mime_type(data)

          "data:#{mime};base64,#{data}"
        end

        def replace_column_type(column_type)
          if column_type.is_a? String
            return column_type == 'Binary' ? 'String' : column_type
          end

          return [replace_column_type(column_type[0])] if column_type.is_a? Array

          column_type.transform_values { |type| replace_column_type(type) }
        end

        def replace_validation(_name, column_schema)
          column_schema.validations
        end

        def bin_to_hex(data)
          data.unpack1('H*')
        end

        def hex_to_bin(data)
          data.scan(/../).map(&:hex).pack('c*')
        end

        def detect_mime_type(base_64_value)
          signatures = {
            'JVBERi0' => 'application/pdf',
            'R0lGODdh' => 'image/gif',
            'R0lGODlh' => 'image/gif',
            'iVBORw0KGgo' => 'image/png',
            'TU0AK' => 'image/tiff',
            '/9j/' => 'image/jpg',
            'UEs' => 'application/vnd.openxmlformats-officedocument.',
            'PK' => 'application/zip'
          }

          signatures.each do |key, value|
            return value if base_64_value.index(key)&.zero?
          end

          'application/octet-stream'
        end
      end
    end
  end
end
