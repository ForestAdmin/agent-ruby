module ForestAdminRpcAgent
  module Routes
    class HealthRoute < BaseRoute
      def initialize
        super('health', 'get', 'rpc_forest')
      end

      def handle_request(_params)
        { status: 'ok', message: 'Forest Admin RPC Agent is running' }.to_json
      end
    end
  end
end
