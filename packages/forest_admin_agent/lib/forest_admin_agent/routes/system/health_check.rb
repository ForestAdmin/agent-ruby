module ForestAdminAgent
  module Routes
    module System
      class HealthCheck < AbstractRoute
        include ForestAdminAgent::Builder
        def setup_routes
          add_route('forest', 'GET', '/', ->(args) { handle_request(args) })

          self
        end

        def handle_request(_args = {})
          config = AgentFactory.instance.container.resolve(:cache).get('config')
          AgentFactory.instance.send_schema(force: true) if config[:is_production] && !config[:skip_schema_update]

          { content: nil, status: 204 }
        end
      end
    end
  end
end
