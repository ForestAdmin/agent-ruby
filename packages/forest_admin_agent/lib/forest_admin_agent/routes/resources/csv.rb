module ForestAdminAgent
  module Routes
    module Resources
      class Csv < AbstractAuthenticatedRoute
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
        include ForestAdminAgent::Utils
        include ForestAdminAgent::Routes::QueryHandler

        def setup_routes
          add_route(
            'forest_list_csv',
            'get',
            '/:collection_name.:format',
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
                parse_query_segment(context.collection, args, context.permissions, context.caller),
                QueryStringParser.parse_condition_tree(
                  context.collection, args
                )
              ]
            ),
            search: QueryStringParser.parse_search(context.collection, args),
            search_extended: QueryStringParser.parse_search_extended(args),
            sort: QueryStringParser.parse_sort(context.collection, args),
            segment: QueryStringParser.parse_segment(context.collection, args)
          )
          projection = QueryStringParser.parse_projection(context.collection, args)
          filename = args[:params][:filename] || args[:params]['collection_name']
          filename += '.csv' unless /\.csv$/i.match?(filename)
          header = args[:params][:header]

          # Generate timestamp for filename
          now = Time.now.strftime('%Y%m%d_%H%M%S')
          filename_with_timestamp = filename.gsub('.csv', "_export_#{now}.csv")

          # Return streaming enumerator instead of full CSV string
          list_records = ->(batch_filter) { context.collection.list(context.caller, batch_filter, projection) }

          {
            content: {
              type: 'Stream',
              enumerator: Utils::CsvGeneratorStream.stream(
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
