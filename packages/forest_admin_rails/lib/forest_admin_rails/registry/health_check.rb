# TODO: move to a new agent package
module ForestAdminRails
  module Registry
    class HealthCheck < AbstractRoute
      def setup_routes
        add_route('forest', 'GET', '/', handle_request)

        self
      end

      def handle_request(_args = {})
        AgentFactory.send_schema(true) if ForestAdminRails.config.is_production

        { content: nil, status: 204 }
      end
    end
  end
end
