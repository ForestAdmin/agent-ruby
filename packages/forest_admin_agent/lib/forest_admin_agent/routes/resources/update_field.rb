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
          context = build(args)

          primary_key_values = Utils::Id.unpack_id(context.collection, args[:params]['id'], with_key: true)
          field_name = args[:params]['field_name']
          array_index = parse_index(args[:params]['index'])

          context.permissions.can?(:edit, context.collection)

          field_schema = context.collection.schema[:fields][field_name]
          validate_array_field!(field_schema, field_name, context.collection)

          record = fetch_record(primary_key_values, context)

          array = record[field_name]
          validate_array_value!(array, field_name, array_index)

          new_value = parse_value_from_body(args[:params], field_schema)

          updated_array = array.dup
          updated_array[array_index] = new_value

          scope = context.permissions.get_scope(context.collection)
          condition_tree = ConditionTree::ConditionTreeFactory.match_records(context.collection, [primary_key_values])
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
            condition_tree: ConditionTree::ConditionTreeFactory.intersect([condition_tree, scope])
          )
          context.collection.update(context.caller, filter, { field_name => updated_array })

          records = context.collection.list(context.caller, filter, ProjectionFactory.all(context.collection))

          {
            name: args[:params]['collection_name'],
            content: JSONAPI::Serializer.serialize(
              records[0],
              is_collection: false,
              class_name: context.collection.name,
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

        def validate_array_field!(field_schema, field_name, collection)
          FieldValidator.validate(collection, field_name)
          return if field_schema.column_type.is_a?(Array)

          raise Http::Exceptions::ValidationError,
                "Field '#{field_name}' is not an array (type: #{field_schema.column_type})"
        rescue ForestAdminDatasourceToolkit::Exceptions::ValidationError => e
          raise Http::Exceptions::NotFoundError, e.message if e.message.include?('not found')

          raise Http::Exceptions::ValidationError, e.message
        end

        def fetch_record(primary_key_values, context)
          scope = context.permissions.get_scope(context.collection)
          condition_tree = ConditionTree::ConditionTreeFactory.match_records(context.collection, [primary_key_values])
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
            condition_tree: ConditionTree::ConditionTreeFactory.intersect([condition_tree, scope])
          )
          records = context.collection.list(context.caller, filter, ProjectionFactory.all(context.collection))

          raise Http::Exceptions::NotFoundError, 'Record not found' unless records&.any?

          records[0]
        end

        def validate_array_value!(array, field_name, array_index)
          unless array.is_a?(Array)
            raise Http::Exceptions::UnprocessableError,
                  "Field '#{field_name}' value is not an array (got: #{array.class})"
          end

          return unless array_index >= array.length

          raise Http::Exceptions::ValidationError,
                "Index #{array_index} out of bounds for array of length #{array.length}"
        end

        def parse_value_from_body(params, field_schema)
          body = params[:data] || {}
          value = body.dig(:attributes, 'value') || body.dig(:attributes, :value)

          coerce_value(value, field_schema.column_type)
        end

        def coerce_value(value, column_type)
          return value unless column_type.is_a?(Array)

          element_type = column_type.first

          if element_type == 'Number' && value.is_a?(String)
            begin
              return Float(value)
            rescue ArgumentError
              raise Http::Exceptions::ValidationError, "Cannot coerce '#{value}' to Number - wrong type"
            end
          end

          value
        end
      end
    end
  end
end
