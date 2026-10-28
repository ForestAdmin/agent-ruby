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

          sort = QueryStringParser.parse_sort(context.collection, args)
          filter = build_context_filter(context.collection, args, context.permissions, context.caller, sort: sort)
          requested = QueryStringParser.parse_requested_projection(context.collection, args)
          projection = context.permissions.redact_projection(
            context.collection,
            requested[:projection],
            named_by_caller: requested[:named_by_caller]
          )
          filename = args[:params][:filename] || args[:params]['collection_name']
          filename += '.csv' unless /\.csv$/i.match?(filename)
          header = Utils::CsvGenerator.filter_header(args[:params][:header], requested[:projection], projection)

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
