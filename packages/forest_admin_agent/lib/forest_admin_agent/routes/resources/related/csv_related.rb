module ForestAdminAgent
  module Routes
    module Resources
      module Related
        class CsvRelated < AbstractRelatedRoute
          include ForestAdminAgent::Utils
          include ForestAdminDatasourceToolkit::Utils
          include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

          def setup_routes
            add_route(
              'forest_related_list_csv',
              'get',
              '/:collection_name/:id/relationships/:relation_name.:format',
              ->(args) { handle_request(args) },
              'csv'
            )

            self
          end

          def handle_request(args = {})
            context = build(args)
            context.permissions.can?(:browse, context.collection)
            context.permissions.can?(:export, context.collection)

            filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
              condition_tree: ConditionTreeFactory.intersect(
                [
                  context.permissions.get_scope(context.collection),
                  ForestAdminAgent::Utils::QueryStringParser.parse_condition_tree(context.child_collection, args)
                ]
              )
            )
            projection = ForestAdminAgent::Utils::QueryStringParser.parse_projection_with_pks(context.child_collection,
                                                                                              args)

            # Get the parent record primary keys
            primary_key_values = Utils::Id.unpack_id(context.collection, args[:params]['id'], with_key: true)
            relation_name = args[:params]['relation_name']

            # Generate timestamp for filename
            now = Time.now.strftime('%Y%m%d_%H%M%S')
            collection_name = args.dig(:params, 'collection_name')
            header = args.dig(:params, 'header')
            filename_with_timestamp = "#{collection_name}_#{relation_name}_export_#{now}.csv"

            # Create a callable to fetch related records
            list_records = lambda do |batch_filter|
              ForestAdminDatasourceToolkit::Utils::Collection.list_relation(
                context.collection,
                primary_key_values,
                relation_name,
                context.caller,
                batch_filter,
                projection
              )
            end

            # For related exports, use list_relation to fetch records
            {
              content: {
                type: 'Stream',
                enumerator: ForestAdminAgent::Utils::CsvGeneratorStream.stream(
                  header,
                  filter,
                  projection,
                  list_records,
                  Facades::Container.config_from_cache[:limit_export_size]
                ),
                headers: {
                  'Content-Type' => 'text/csv; charset=utf-8',
                  'Content-Disposition' => "attachment; filename=\"#{filename_with_timestamp}\"",
                  'Cache-Control' => 'no-cache',
                  'X-Accel-Buffering' => 'no'
                }
              },
              status: 200
            }
          end
        end
      end
    end
  end
end
