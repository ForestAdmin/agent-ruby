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
          relations = linked_one_to_one_relations(args, context)
          assert_can_edit_linked_collections(relations, context)
          data = format_attributes(args, context.collection)
          record = context.collection.create(context.caller, data)
          link_one_to_one_relations(relations, record, context)
          id = ForestAdminDatasourceToolkit::Utils::Record.primary_keys(context.collection, record)
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
            condition_tree: ConditionTree::ConditionTreeFactory.match_ids(context.collection, [id])
          )
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

        def assert_can_edit_linked_collections(relations, context)
          relations.each { |relation| context.permissions.can?(:edit, relation[:foreign_collection]) }
        end

        def linked_one_to_one_relations(args, context)
          args[:params][:data][:relationships]&.filter_map do |field, value|
            schema = context.collection.schema[:fields][field]
            next unless %w[OneToOne PolymorphicOneToOne].include?(schema.type)

            id = value.dig('data', 'id')
            next if id.nil?

            {
              schema: schema,
              foreign_collection: context.datasource.get_collection(schema.foreign_collection),
              id: id
            }
          end || []
        end

        def link_one_to_one_relations(relations, record, context)
          relations.each do |relation|
            schema = relation[:schema]
            foreign_collection = relation[:foreign_collection]
            primary_key_values = Utils::Id.unpack_id(foreign_collection, relation[:id], with_key: true)
            origin_value = record[schema.origin_key_target]

            patch = { schema.origin_key => origin_value }
            if schema.type == 'PolymorphicOneToOne'
              patch[schema.origin_type_field] =
                context.collection.name.gsub('__', '::')
            end
            new_fk_owner = ConditionTree::ConditionTreeFactory.match_records(foreign_collection, [primary_key_values])
            filter = Filter.new(
              condition_tree: ConditionTree::ConditionTreeFactory.intersect(
                [
                  context.permissions.get_scope(foreign_collection),
                  new_fk_owner
                ]
              )
            )
            foreign_collection.update(context.caller, filter, patch)
          end
        end
      end
    end
  end
end
