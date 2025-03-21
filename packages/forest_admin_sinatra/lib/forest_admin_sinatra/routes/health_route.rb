module ForestAdminSinatra
  module Routes
    class HealthRoute < BaseRoute
      def initialize
        super('health', 'get', 'forest_health')
      end

      def handle_request(_params)
        { status: 'ok', message: 'Forest Admin Agent Sinatra is running' }.to_json
      end
    end
  end
end
