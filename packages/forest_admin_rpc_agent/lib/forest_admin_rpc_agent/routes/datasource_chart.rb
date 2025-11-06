require 'jsonapi-serializers'

module ForestAdminRpcAgent
  module Routes
    class DatasourceChart < BaseRoute
      def initialize
        super('rpc-datasource-chart', 'post', 'rpc_chart_datasource')
      end

      def handle_request(args)
        return {} unless args[:params]['chart']

        chart_name = args[:params]['chart']
        datasource = ForestAdminRpcAgent::Facades::Container.datasource

        datasource.render_chart(args[:caller], chart_name)
      end
    end
  end
end
