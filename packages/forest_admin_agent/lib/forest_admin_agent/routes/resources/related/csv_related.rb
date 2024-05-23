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
            id = Utils::Id.unpack_id(@collection, args[:params]['id'], with_key: true)
            records = Collection.list_relation(
              @collection,
              id,
              args[:params]['relation_name'],
              @caller,
              filter,
              projection
            )

            filename = args[:params][:filename] || "#{args[:params]["relation_name"]}.csv"
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
end
