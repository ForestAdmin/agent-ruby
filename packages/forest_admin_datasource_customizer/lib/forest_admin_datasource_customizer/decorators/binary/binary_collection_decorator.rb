require 'base64'
require 'marcel'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Binary
      class BinaryCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit
        include ForestAdminDatasourceToolkit::Decorators
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

        OPERATORS_WITH_REPLACEMENT = [Operators::AFTER, Operators::BEFORE, Operators::CONTAINS,
                                      Operators::ENDS_WITH, Operators::EQUAL, Operators::GREATER_THAN,
                                      Operators::I_CONTAINS, Operators::NOT_IN, Operators::I_ENDS_WITH,
                                      Operators::I_STARTS_WITH, Operators::LESS_THAN, Operators::NOT_CONTAINS,
                                      Operators::NOT_EQUAL, Operators::STARTS_WITH, Operators::IN].freeze

        def initialize(child_collection, datasource)
          super
          @use_hex_conversion = {}
        end

        def set_binary_mode(name, type)
          field = @child_collection.schema[:fields][name]

          raise ForestAdminAgent::Http::Exceptions::BadRequestError, 'Invalid binary mode' unless %w[datauri
                                                                                                     hex].include?(type)

          unless field&.type == 'Column' && field&.column_type == 'Binary'
            raise ForestAdminAgent::Http::Exceptions::BadRequestError, 'Expected a binary field'
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

        def refine_filter(_caller, filter = nil)
          filter&.override(
            condition_tree: filter&.condition_tree&.replace_leafs do |leaf|
              convert_condition_tree_leaf(leaf)
            end
          )
        end

        def create(caller, data)
          data_with_binary = convert_record(true, data)
          record = super(caller, data_with_binary)

          convert_record(false, record)
        end

        def list(caller, filter, projection)
          records = super
          records.map! { |record| convert_record(false, record) }

          records
        end

        def update(caller, filter, patch)
          super(caller, filter, convert_record(true, patch))
        end

        def aggregate(caller, filter, aggregation, limit = nil)
          rows = super
          rows.map! do |row|
            {
              'value' => row['value'],
              'group' => row['group'].to_h { |path, value| [path, convert_value(false, path, value)] }
            }
          end
        end

        def convert_condition_tree_leaf(leaf)
          prefix, suffix = leaf.field.split(':')
          schema = @child_collection.schema[:fields][prefix]

          if schema.type != 'Column'
            condition_tree = @datasource.get_collection(schema.foreign_collection).convert_condition_tree_leaf(
              leaf.override(field: suffix)
            )

            return condition_tree.nest(prefix)
          end

          if OPERATORS_WITH_REPLACEMENT.include?(leaf.operator)
            column_type = if [Operators::IN, Operators::NOT_IN].include?(leaf.operator)
                            [schema.column_type]
                          else
                            schema.column_type
                          end

            return leaf.override(
              value: convert_value_helper(true, column_type, should_use_hex(prefix), leaf.value)
            )
          end

          leaf
        end

        def should_use_hex(name)
          return @use_hex_conversion[name] if @use_hex_conversion.key?(name)

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

          return value if field.type == 'PolymorphicManyToOne'

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
            return use_hex ? BinaryHelper.hex_to_bin(value) : Base64.strict_decode64(value.partition(',')[2])
          end

          return BinaryHelper.bin_to_hex(value) if use_hex

          data = Base64.strict_encode64(value)
          mime = Marcel::MimeType.for StringIO.new(value)

          "data:#{mime};base64,#{data}"
        end

        def replace_column_type(column_type)
          if column_type.is_a? String
            return column_type == 'Binary' ? 'String' : column_type
          end

          return [replace_column_type(column_type[0])] if column_type.is_a? Array

          column_type.transform_values { |type| replace_column_type(type) }
        end

        def replace_validation(name, column_schema)
          if column_schema.column_type == 'Binary'
            validations = []
            min_length = (column_schema.validations.find { |v| v[:operator] == Operators::LONGER_THAN } || {})[:value]
            max_length = (column_schema.validations.find { |v| v[:operator] == Operators::SHORTER_THAN } || {})[:value]

            if should_use_hex(name)
              validations << { operator: Operators::MATCH, value: '/^[0-9a-f]+$/' }
              validations << { operator: Operators::LONGER_THAN, value: (min_length * 2) + 1 } if min_length
              validations << { operator: Operators::SHORTER_THAN, value: (max_length * 2) - 1 } if max_length
            else
              validations << { operator: Operators::MATCH, value: '/^data:.*;base64,.*/' }
            end

            if column_schema.validations.find { |v| v[:operator] == Operators::PRESENT }
              validations << { operator: Operators::PRESENT }
            end

            return validations
          end

          column_schema.validations
        end
      end
    end
  end
end
