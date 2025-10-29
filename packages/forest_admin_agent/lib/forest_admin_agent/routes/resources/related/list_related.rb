require 'jsonapi-serializers'

module ForestAdminAgent
  module Routes
    module Resources
      module Related
        class ListRelated < AbstractRelatedRoute
          include ForestAdminAgent::Builder
          include ForestAdminDatasourceToolkit::Utils
          include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

          def setup_routes
            add_route(
              'forest_related_list',
              'get',
              '/:collection_name/:id/relationships/:relation_name',
              ->(args) { handle_request(args) }
            )

            self
          end

          def handle_request(args = {})
            context = build(args)
            context.permissions.can?(:browse, context.collection)

            filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
              condition_tree: ConditionTreeFactory.intersect(
                [
                  context.permissions.get_scope(context.collection),
                  ForestAdminAgent::Utils::QueryStringParser.parse_condition_tree(context.child_collection, args)
                ]
              ),
              page: ForestAdminAgent::Utils::QueryStringParser.parse_pagination(args),
              sort: ForestAdminAgent::Utils::QueryStringParser.parse_sort(context.child_collection, args)
            )
            projection = ForestAdminAgent::Utils::QueryStringParser.parse_projection_with_pks(context.child_collection,
                                                                                              args)
            primary_key_values = Utils::Id.unpack_id(context.collection, args[:params]['id'], with_key: true)
            records = Collection.list_relation(
              context.collection,
              primary_key_values,
              args[:params]['relation_name'],
              context.caller,
              filter,
              projection
            )

            {
              name: context.child_collection.name,
              content: JSONAPI::Serializer.serialize(
                records,
                is_collection: true,
                class_name: context.child_collection.name,
                serializer: Serializer::ForestSerializer,
                include: projection.relations.keys
              )
            }
          end
        end
      end
    end
  end
end
