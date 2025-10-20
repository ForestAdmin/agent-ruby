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
          @collection.update(@caller, filter, { field_name => updated_array })

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
          FieldValidator.validate(@collection, field_name)
          return if field_schema.column_type.to_s.start_with?('[')

          raise Http::Exceptions::ValidationError,
                "Field '#{field_name}' is not an array (type: #{field_schema.column_type})"
        rescue ForestAdminDatasourceToolkit::Exceptions::ValidationError => e
          raise Http::Exceptions::NotFoundError, e.message if e.message.include?('not found')

          raise Http::Exceptions::ValidationError, e.message
        end

        def fetch_record(record_id)
          scope = @permissions.get_scope(@collection)
          condition_tree = ConditionTree::ConditionTreeFactory.match_records(@collection, [record_id])
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
            condition_tree: ConditionTree::ConditionTreeFactory.intersect([condition_tree, scope])
          )
          records = @collection.list(@caller, filter, ProjectionFactory.all(@collection))

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

        def parse_value_from_body(params, _field_schema)
          body = params[:data] || {}
          body.dig(:attributes, 'value') || body.dig(:attributes, :value)
        end
      end
    end
  end
end
