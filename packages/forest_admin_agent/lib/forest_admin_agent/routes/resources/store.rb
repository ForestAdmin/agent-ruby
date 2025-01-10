require 'jsonapi-serializers'
require 'ostruct'

module ForestAdminAgent
  module Routes
    module Resources
      class Store < AbstractAuthenticatedRoute
        include ForestAdminAgent::Builder
        include ForestAdminDatasourceToolkit::Components::Query
        def setup_routes
          add_route('forest_store', 'post', '/:collection_name', ->(args) { handle_request(args) })

          self
        end

        def handle_request(args = {})
          build(args)
          @permissions.can?(:add, @collection)
          data = format_attributes(args)
          record = @collection.create(@caller, data)
          link_one_to_one_relations(args, record)

          id = Utils::Id.unpack_id(@collection, record['id'], with_key: true)
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
            condition_tree: ConditionTree::ConditionTreeFactory.match_records(@collection, [id])
          )
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

        def link_one_to_one_relations(args, record)
          args[:params][:data][:relationships]&.map do |field, value|
            schema = @collection.schema[:fields][field]
            next unless ['OneToOne', 'PolymorphicOneToOne'].include?(schema.type)

            id = Utils::Id.unpack_id(@collection, value['data']['id'], with_key: true)
            foreign_collection = @datasource.get_collection(schema.foreign_collection)
            # Load the value that will be used as origin_key
            origin_value = record[schema.origin_key_target]

            # update new relation (may update zero or one records).
            patch = { schema.origin_key => origin_value }
            patch[schema.origin_type_field] = @collection.name.gsub('__', '::') if schema.type == 'PolymorphicOneToOne'
            condition_tree = ConditionTree::ConditionTreeFactory.match_records(foreign_collection, [id])
            filter = Filter.new(condition_tree: condition_tree)
            foreign_collection.update(@caller, filter, patch)
          end
        end
      end
    end
  end
end
