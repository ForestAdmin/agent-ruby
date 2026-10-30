require 'jsonapi-serializers'

module ForestAdminAgent
  module Routes
    module Resources
      module Related
        class ListRelated < AbstractRelatedRoute
          include ForestAdminAgent::Builder
          include ForestAdminDatasourceToolkit::Utils
          include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
          include ForestAdminAgent::Routes::QueryHandler

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
            context.permissions.can?(:browse, context.child_collection)
            sort = ForestAdminAgent::Utils::QueryStringParser.parse_sort(context.child_collection, args)
            filter = build_context_filter(context.child_collection, args, context.permissions, context.caller,
                                          sort: sort)
                     .override(page: ForestAdminAgent::Utils::QueryStringParser.parse_pagination(args))
            projection = redacted_projection_with_pks(context, context.child_collection, args)
            primary_key_values = Utils::Id.unpack_id(context.collection, args[:params]['id'], with_key: true)
            relation_scopes = context.permissions.relation_scopes(context.child_collection, projection)
            records = relation_scopes.redact(
              Collection.list_relation(
                context.collection,
                primary_key_values,
                args[:params]['relation_name'],
                context.caller,
                filter,
                relation_scopes.with_scope_fields(projection)
              ),
              projection,
              context.caller.timezone
            )

            {
              name: context.child_collection.name,
              content: JSONAPI::Serializer.serialize(
                records,
                is_collection: true,
                class_name: context.child_collection.name,
                serializer: Serializer::ForestSerializer,
                include: projection.relation_include_paths
              )
            }
          end
        end
      end
    end
  end
end
