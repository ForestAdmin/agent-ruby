require 'jsonapi-serializers'

module ForestAdminRpcAgent
  module Routes
    class List < BaseRoute
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminAgent::Utils
      include ForestAdminAgent::Routes::QueryHandler

      def initialize
        super('rpc/:collection_name/list', 'get', 'rpc_list')
      end

      def handle_request(args)
        return '{}' unless args[:params]['collection_name']

        caller = ForestAdminDatasourceToolkit::Components::Caller.new(
          **args[:params]['caller'].to_h.transform_keys(&:to_sym)
        )
        datasource = ForestAdminRpcAgent::Facades::Container.datasource
        collection = datasource.get_collection(args[:params]['collection_name'])
        projection = ForestAdminDatasourceToolkit::Components::Query::Projection.new(args[:params]['projection'])
        filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new
        # condition_tree: ConditionTreeFactory.intersect(
        #   [
        #     QueryStringParser.parse_condition_tree(collection, args),
        #     # parse_query_segment(collection, args, @permissions, @caller)
        #   ]
        # ),
        # page: QueryStringParser.parse_pagination(params),
        # search: QueryStringParser.parse_search(@collection, params),
        # search_extended: QueryStringParser.parse_search_extended(params),
        # sort: QueryStringParser.parse_sort(@collection, params),
        # segment: QueryStringParser.parse_segment(@collection, params)

        collection.list(caller, filter, projection).to_json
      end
    end
  end
end
