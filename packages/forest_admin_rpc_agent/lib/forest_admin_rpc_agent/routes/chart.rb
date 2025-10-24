require 'jsonapi-serializers'

module ForestAdminRpcAgent
  module Routes
    class Chart < BaseRoute
      include ForestAdminDatasourceToolkit::Components::Query

      def initialize
        super('rpc/:collection_name/chart', 'post', 'rpc_chart_collection')
      end

      def handle_request(args)
        return '{}' unless args[:params]['collection_name']

        chart_name = args[:params]['name']
        caller = ForestAdminDatasourceToolkit::Components::Caller.new(
          **args[:params]['caller'].to_h.transform_keys(&:to_sym)
        )
        datasource = ForestAdminRpcAgent::Facades::Container.datasource
        collection = datasource.get_collection(args[:params]['collection_name'])

        primary_key_values = ForestAdminAgent::Utils::Id.unpack_id(collection, args[:params]['record_id'])
        collection.render_chart(caller, chart_name, primary_key_values)
      end
    end
  end
end
