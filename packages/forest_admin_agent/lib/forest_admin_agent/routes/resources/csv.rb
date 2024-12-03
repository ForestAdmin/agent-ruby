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
                ForestAdminAgent::Utils::QueryStringParser.parse_condition_tree(
                  @collection, args
                )
              ]
            ),
            search: ForestAdminAgent::Utils::QueryStringParser.parse_search(@collection, args),
            search_extended: ForestAdminAgent::Utils::QueryStringParser.parse_search_extended(args)
          )
          projection = ForestAdminAgent::Utils::QueryStringParser.parse_projection(@collection, args)
          records = @collection.list(@caller, filter, projection)
          filename = args[:params][:filename] || "#{args[:params]["collection_name"]}.csv"
          filename += '.csv' unless /\.csv$/i.match?(filename)

          {
            content: {
              export: CsvGenerator.generate(records, projection)
            },
            filename: filename
          }
        end
      end
    end
  end
end
