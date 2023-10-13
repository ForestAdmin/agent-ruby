require 'jsonapi-serializers'

module ForestAdminAgent
  module Routes
    module Resources
      class Count < AbstractRoute
        include ForestAdminAgent::Builder
        def setup_routes
          add_route('forest_count', 'get', '/:collection_name/count', ->(args) { handle_request(args) })

          self
        end

        def handle_request(args = {})
          build(args)
          caller = ForestAdminAgent::Utils::QueryStringParser.parse_caller(args)
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new
          aggregation = ForestAdminDatasourceToolkit::Components::Query::Aggregation.new(operation: 'Count')
          result = @collection.aggregate(caller, filter, aggregation)

          {
            name: args[:params]['collection_name'],
            content: {
              count: result[0][:value]
            }
          }
        end
      end
    end
  end
end
