module ForestAdminRpcAgent
  module Routes
    class HealthRoute < BaseRoute
      def initialize
        super('/', 'get', 'rpc_forest')
      end

      def handle_request(_params)
        { error: nil, message: 'Agent is running' }
      end
    end
  end
end
