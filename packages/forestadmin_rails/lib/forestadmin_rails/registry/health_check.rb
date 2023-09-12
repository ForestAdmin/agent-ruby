# TODO: move to a new agent package
module ForestadminRails
  module Registry
    class HealthCheck < AbstractRoute
      def setup_routes
        add_route('aaaaa', 'GET', '/', handle_request)

        self
      end

      def handle_request(_args = {})
        AgentFactory.send_schema(true) if ForestadminRails.config.is_production

        { content: nil, status: 204 }
      end
    end
  end
end
