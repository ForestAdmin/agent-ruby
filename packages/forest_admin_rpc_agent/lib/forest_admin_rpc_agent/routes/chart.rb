require 'jsonapi-serializers'

module ForestAdminRpcAgent
  module Routes
    class Chart < BaseRoute
      include ForestAdminDatasourceToolkit::Components::Query

      def initialize
        super('rpc/:collection_name/chart', 'post', 'rpc_chart_collection')
      end

      def handle_request(args)
        return {} unless args[:params]['collection_name']

        chart_name = args[:params]['chart']
        datasource = ForestAdminRpcAgent::Facades::Container.datasource
        collection = get_collection_safe(datasource, args[:params]['collection_name'])

        collection.render_chart(caller, chart_name, args[:params]['record_id'])
      end
    end
  end
end
