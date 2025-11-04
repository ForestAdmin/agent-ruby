require 'jsonapi-serializers'

module ForestAdminRpcAgent
  module Routes
    class DatasourceChart < BaseRoute
      def initialize
        super('rpc-datasource-chart', 'post', 'rpc_chart_datasource')
      end

      def handle_request(args)
        return '{}' unless args[:params]['chart']

        chart_name = args[:params]['chart']
        caller = ForestAdminDatasourceToolkit::Components::Caller.new(
          **args[:params]['caller'].to_h.transform_keys(&:to_sym)
        )
        datasource = ForestAdminRpcAgent::Facades::Container.datasource

        datasource.render_chart(caller, chart_name).to_json
      end
    end
  end
end
