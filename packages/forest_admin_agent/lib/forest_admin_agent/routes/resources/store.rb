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
          relations = authorized_linked_one_to_one_relations(args, context)
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

        def authorized_linked_one_to_one_relations(args, context)
          linked_one_to_one_relations(args, context).map do |relation|
            foreign_collection = relation[:foreign_collection]

            context.permissions.can?(:edit, foreign_collection)

            relation.merge(
              scope: context.permissions.get_scope(foreign_collection),
              primary_key_values: Utils::Id.unpack_id(foreign_collection, relation[:id], with_key: true)
            )
          end
        end

        def linked_one_to_one_relations(args, context)
          relationships = args.dig(:params, :data, :relationships) || {}

          relationships.filter_map { |field, value| linked_one_to_one_relation(field, value, context) }
        end

        def linked_one_to_one_relation(field, value, context)
          schema = context.collection.schema[:fields][field]
          return unless %w[OneToOne PolymorphicOneToOne].include?(schema.type)

          id = value.dig('data', 'id')
          return if id.nil?

          {
            schema: schema,
            foreign_collection: context.datasource.get_collection(schema.foreign_collection),
            id: id
          }
        end

        def link_one_to_one_relations(relations, record, context)
          relations.each do |relation|
            schema = relation[:schema]
            foreign_collection = relation[:foreign_collection]

            patch = { schema.origin_key => record[schema.origin_key_target] }
            if schema.type == 'PolymorphicOneToOne'
              patch[schema.origin_type_field] =
                context.collection.name.gsub('__', '::')
            end

            new_fk_owner = ConditionTree::ConditionTreeFactory.match_records(
              foreign_collection, [relation[:primary_key_values]]
            )
            filter = Filter.new(
              condition_tree: ConditionTree::ConditionTreeFactory.intersect(
                [
                  relation[:scope],
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
