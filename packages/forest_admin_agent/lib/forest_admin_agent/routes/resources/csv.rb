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
          build(args)
          @permissions.can?(:browse, @collection)
          @permissions.can?(:export, @collection)
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
            condition_tree: ConditionTreeFactory.intersect(
              [
                @permissions.get_scope(@collection),
                parse_query_segment(@collection, args, @permissions, @caller),
                QueryStringParser.parse_condition_tree(
                  @collection, args
                )
              ]
            ),
            search: QueryStringParser.parse_search(@collection, args),
            search_extended: QueryStringParser.parse_search_extended(args),
            sort: QueryStringParser.parse_sort(@collection, args),
            segment: QueryStringParser.parse_segment(@collection, args)
          )
          projection = QueryStringParser.parse_projection(@collection, args)
          filename = args[:params][:filename] || args[:params]['collection_name']
          filename += '.csv' unless /\.csv$/i.match?(filename)
          header = args[:params][:header]

          # Generate timestamp for filename
          now = Time.now.strftime('%Y%m%d_%H%M%S')
          filename_with_timestamp = filename.gsub('.csv', "_export_#{now}.csv")

          # Return streaming enumerator instead of full CSV string
          {
            content: {
              type: 'Stream',
              enumerator: Utils::CsvGeneratorStream.stream(
                @collection,
                @caller,
                header,
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
