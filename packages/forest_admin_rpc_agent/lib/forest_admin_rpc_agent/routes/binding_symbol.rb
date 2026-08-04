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
        count = Integer(value, exception: false) || 0
        return 0 if count.negative?

        if count > MAX_BINDS_COUNT
          raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                "binds_count (#{count}) exceeds the maximum supported value of #{MAX_BINDS_COUNT}."
        end

        count
      end
    end
  end
end
