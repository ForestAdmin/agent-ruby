require 'jsonapi-serializers'
require 'ostruct'

module ForestAdminAgent
  module Routes
    module Resources
      class Store < AbstractAuthenticatedRoute
        include ForestAdminAgent::Builder
        def setup_routes
          add_route('forest_store', 'post', '/:collection_name', ->(args) { handle_request(args) })

          self
        end

        def handle_request(args = {})
          build(args)
          data = format_attributes(args)
          record = @collection.create(@caller, data)
          link_one_to_one_relations(args, record)

          {
            name: args[:params]['collection_name'],
            content: JSONAPI::Serializer.serialize(
              record,
              is_collection: false,
              serializer: Serializer::ForestSerializer
            )
          }
        end

        def link_one_to_one_relations(args, record)
          relations = {}

          args[:params][:data][:relationships]&.map do |field, value|
            schema = @collection.fields[field]
            if schema.type == 'OneToOne'
              id = Utils::Id.unpack_id(@collection, value['data']['id'], with_key: true)
              relations[field] = id
              foreign_collection = @datasource.collection(schema.foreign_collection)
              # Load the value that will be used as origin_key
              origin_value = record[schema.origin_key_target]

              # update new relation (may update zero or one records).
              # TODO: replace by ConditionTreeFactory.matchRecords(foreignCollection.schema, [linked]);
              condition_tree = OpenStruct.new(field: 'id', operator: 'EQUAL', value: id['id'])
              filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(condition_tree: condition_tree)
              foreign_collection.update(@caller, filter, { schema.origin_key => origin_value })
            end
          end
        end
      end
    end
  end
end
