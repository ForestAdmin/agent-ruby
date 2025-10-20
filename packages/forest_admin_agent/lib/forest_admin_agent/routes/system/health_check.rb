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
          { content: nil, status: 204 }
        end
      end
    end
  end
end
