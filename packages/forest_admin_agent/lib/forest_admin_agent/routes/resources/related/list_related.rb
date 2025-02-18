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
            build(args)
            @permissions.can?(:browse, @collection)

            filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
              condition_tree: ConditionTreeFactory.intersect(
                [
                  @permissions.get_scope(@collection),
                  ForestAdminAgent::Utils::QueryStringParser.parse_condition_tree(@child_collection, args)
                ]
              ),
              page: ForestAdminAgent::Utils::QueryStringParser.parse_pagination(args),
              sort: ForestAdminAgent::Utils::QueryStringParser.parse_sort(@child_collection, args)
            )
            projection = ForestAdminAgent::Utils::QueryStringParser.parse_projection_with_pks(@child_collection, args)
            id = Utils::Id.unpack_id(@collection, args[:params]['id'], with_key: true)
            records = Collection.list_relation(
              @collection,
              id,
              args[:params]['relation_name'],
              @caller,
              filter,
              projection
            )

            {
              name: @child_collection.name,
              content: JSONAPI::Serializer.serialize(
                records,
                is_collection: true,
                class_name: @child_collection.name,
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
