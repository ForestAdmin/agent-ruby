module ForestAdminRpcAgent
  module Routes
    class HealthRoute < BaseRoute
      def initialize
        super('/', 'get', 'rpc_forest')
      end

      def handle_request(_params)
        { content: nil, status: 204 }
      end
    end
  end
end
