# frozen_string_literal: true

require 'jsonapi-serializers'

module ForestAdminAgent
  module Routes
    module Resources
      class UpdateField < AbstractAuthenticatedRoute
        include ForestAdminAgent::Builder
        include ForestAdminDatasourceToolkit::Components::Query
        include ForestAdminDatasourceToolkit::Validations
        include ForestAdminDatasourceToolkit::Schema

        def setup_routes
          add_route(
            'forest_update_field',
            'put',
            '/:collection_name/:id/relationships/:field_name/:index',
            ->(args) { handle_request(args) }
          )

          self
        end

        def handle_request(args = {})
          build(args)

          record_id = Utils::Id.unpack_id(@collection, args[:params]['id'], with_key: true)
          field_name = args[:params]['field_name']
          array_index = parse_index(args[:params]['index'])

          @permissions.can?(:edit, @collection)

          field_schema = @collection.schema[:fields][field_name]
          validate_array_field!(field_schema, field_name)

          record = fetch_record(record_id)

          array = record[field_name]
          validate_array_value!(array, field_name, array_index)

          new_value = parse_value_from_body(args[:params], field_schema)

          updated_array = array.dup
          updated_array[array_index] = new_value

          scope = @permissions.get_scope(@collection)
          condition_tree = ConditionTree::ConditionTreeFactory.match_records(@collection, [record_id])
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
            condition_tree: ConditionTree::ConditionTreeFactory.intersect([condition_tree, scope])
          )
          @collection.update(@caller, filter, { field_name.to_sym => updated_array })

          records = @collection.list(@caller, filter, ProjectionFactory.all(@collection))

          {
            name: args[:params]['collection_name'],
            content: JSONAPI::Serializer.serialize(
              records[0],
              is_collection: false,
              class_name: @collection.name,
              serializer: Serializer::ForestSerializer
            )
          }
        end

        private

        def parse_index(index_param)
          index = Integer(index_param)
          raise Http::Exceptions::ValidationError, 'Index must be non-negative' if index.negative?

          index
        rescue ArgumentError
          raise Http::Exceptions::ValidationError, "Invalid index: #{index_param}"
        end

        def validate_array_field!(field_schema, field_name)
          begin
            FieldValidator.validate(@collection, field_name)
          rescue ForestAdminDatasourceToolkit::Exceptions::ValidationError => e
            if e.message.include?('not found')
              raise Http::Exceptions::NotFoundError, e.message
            else
              raise Http::Exceptions::ValidationError, e.message
            end
          end

          # Check if column type is an array
          column_type = field_schema[:column_type]
          unless column_type.to_s.start_with?('[')
            raise Http::Exceptions::ValidationError,
                  "Field '#{field_name}' is not an array (type: #{column_type})"
          end
        end

        def fetch_record(record_id)
          scope = @permissions.get_scope(@collection)
          condition_tree = ConditionTree::ConditionTreeFactory.match_records(@collection, [record_id])
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
            condition_tree: ConditionTree::ConditionTreeFactory.intersect([condition_tree, scope])
          )
          records = @collection.list(@caller, filter, ProjectionFactory.all(@collection))

          unless records&.any?
            raise Http::Exceptions::NotFoundError, 'Record not found'
          end

          records[0]
        end

        def validate_array_value!(array, field_name, array_index)
          unless array.is_a?(Array)
            raise Http::Exceptions::UnprocessableError,
                  "Field '#{field_name}' value is not an array (got: #{array.class})"
          end

          if array_index >= array.length
            raise Http::Exceptions::ValidationError,
                  "Index #{array_index} out of bounds for array of length #{array.length}"
          end
        end

        def parse_value_from_body(params, field_schema)
          # Expected format: { data: { attributes: { value: <new_value> } } }
          body = params[:data] || {}
          value = body.dig(:attributes, 'value') || body.dig(:attributes, :value)

          element_type = extract_element_type(field_schema[:column_type])

          element_schema = ColumnSchema.new(column_type: element_type)

          FieldValidator.validate_value(field_schema[:column_type], element_schema, value)

          value
        rescue ForestAdminDatasourceToolkit::Exceptions::ValidationError => e
          raise Http::Exceptions::ValidationError, e.message
        end

        # Extract element type from array column type
        # E.g., "[String]" → "String", "[Number]" → "Number"
        def extract_element_type(column_type)
          type_str = column_type.to_s
          if type_str.start_with?('[') && type_str.end_with?(']')
            type_str[1..-2]
          else
            PrimitiveType::STRING
          end
        end
      end
    end
  end
end
