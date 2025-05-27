require 'jsonapi-serializers'

module ForestAdminRpcAgent
  module Routes
    class Aggregate < BaseRoute
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminAgent::Utils
      include ForestAdminAgent::Routes::QueryHandler

      def initialize
        super('rpc/:collection_name/aggregate', 'post', 'rpc_aggregate')
      end

      def handle_request(args)
        return '{}' unless args[:params]['collection_name']

        caller = ForestAdminDatasourceToolkit::Components::Caller.new(
          **args[:params]['caller'].to_h.transform_keys(&:to_sym)
        )
        datasource = ForestAdminRpcAgent::Facades::Container.datasource
        collection = datasource.get_collection(args[:params]['collection_name'])

        aggregation = Aggregation.new(
          operation: args[:params]['aggregation']['operation'],
          field: args[:params]['aggregation']['field'],
          groups: args[:params]['aggregation']['groups']
        )
        filter = FilterFactory.from_plain_object(args[:params]['filter'])

        collection.aggregate(caller, filter, aggregation, args[:params]['limit']).to_json
      end
    end
  end
end
