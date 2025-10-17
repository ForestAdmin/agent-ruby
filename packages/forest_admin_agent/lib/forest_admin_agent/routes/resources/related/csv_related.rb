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
            build(args)
            @permissions.can?(:browse, @collection)
            @permissions.can?(:export, @collection)

            filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
              condition_tree: ConditionTreeFactory.intersect(
                [
                  @permissions.get_scope(@collection),
                  ForestAdminAgent::Utils::QueryStringParser.parse_condition_tree(@child_collection, args)
                ]
              )
            )
            projection = ForestAdminAgent::Utils::QueryStringParser.parse_projection_with_pks(@child_collection, args)

            filename = args[:params][:filename] || "#{args[:params]["relation_name"]}.csv"
            filename += '.csv' unless /\.csv$/i.match?(filename)

            # Generate timestamp for filename
            now = Time.now.strftime('%Y%m%d_%H%M%S')
            collection_name = args[:params]["collection_name"]
            relation_name = args[:params]["relation_name"]
            filename_with_timestamp = "#{collection_name}_#{relation_name}_export_#{now}.csv"

            # For related exports, we need to create a streaming-compatible approach
            # We'll use the child collection's list method with proper filtering
            {
              content: {
                type: 'Stream',
                enumerator: ForestAdminAgent::Utils::CsvGeneratorStream.stream(
                  @child_collection,
                  @caller,
                  filter,
                  projection,
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
