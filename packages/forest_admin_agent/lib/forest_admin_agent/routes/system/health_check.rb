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
          if AgentFactory.instance.container.resolve(:cache).get('config')[:is_production]
            AgentFactory.send_schema(true)
          end

          { content: nil, status: 204 }
        end
      end
    end
  end
end
