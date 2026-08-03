module ForestAdminRpcAgent
  module Routes
    class BindingSymbol < BaseRoute
      MAX_BINDS_COUNT = 10_000

      def initialize
        super('rpc-binding-symbol', 'post', 'rpc_binding_symbol')
      end

      def handle_request(args)
        connection_name = args[:params]['connection_name']
        datasource = ForestAdminRpcAgent::Facades::Container.datasource

        datasource.build_binding_symbol(connection_name, Array.new(parse_binds_count(args[:params]['binds_count'])))
      end

      private

      def parse_binds_count(value)
        (Integer(value, exception: false) || 0).clamp(0, MAX_BINDS_COUNT)
      end
    end
  end
end
