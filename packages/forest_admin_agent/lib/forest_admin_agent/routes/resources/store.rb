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
          context = build(args)
          context.permissions.can?(:add, context.collection)
          data = format_attributes(args, context.collection)
          record = context.collection.create(context.caller, data)
          link_one_to_one_relations(args, record, context)
          id = ForestAdminDatasourceToolkit::Utils::Record.primary_keys(context.collection, record)
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
            condition_tree: ConditionTree::ConditionTreeFactory.match_ids(context.collection, [id])
          )
          records = context.collection.list(context.caller, filter,
                                            ProjectionFactory.all(context.collection, context.datasource))

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

        def link_one_to_one_relations(args, record, context)
          args[:params][:data][:relationships]&.map do |field, value|
            schema = context.collection.schema[:fields][field]
            next unless %w[OneToOne PolymorphicOneToOne].include?(schema.type)

            primary_key_values = Utils::Id.unpack_id(context.collection, value['data']['id'], with_key: true)
            foreign_collection = context.datasource.get_collection(schema.foreign_collection)
            # Load the value that will be used as origin_key
            origin_value = record[schema.origin_key_target]

            # update new relation (may update zero or one records).
            patch = { schema.origin_key => origin_value }
            if schema.type == 'PolymorphicOneToOne'
              # Use helper to convert collection name to polymorphic class name (handles renaming)
              patch[schema.origin_type_field] = get_polymorphic_class_name_for_collection(
                context.datasource,
                context.collection.name
              )
            end
            condition_tree = ConditionTree::ConditionTreeFactory.match_records(foreign_collection, [primary_key_values])
            filter = Filter.new(condition_tree: condition_tree)
            foreign_collection.update(context.caller, filter, patch)
          end
        end
      end
    end
  end
end
