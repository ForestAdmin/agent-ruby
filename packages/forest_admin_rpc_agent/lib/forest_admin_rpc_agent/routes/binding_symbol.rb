module ForestAdminRpcAgent
  module Routes
    class BindingSymbol < BaseRoute
      def initialize
        super('rpc-binding-symbol', 'post', 'rpc_binding_symbol')
      end

      def handle_request(args)
        connection_name = args[:params]['connection_name']
        binds_count = args[:params]['binds_count'].to_i
        datasource = ForestAdminRpcAgent::Facades::Container.datasource

        datasource.build_binding_symbol(connection_name, Array.new(binds_count))
      end
    end
  end
end
