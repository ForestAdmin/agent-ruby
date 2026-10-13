module ForestAdminAgent
  module Routes
    module Security
      class ScopeInvalidation < AbstractAuthenticatedRoute
        include ForestAdminAgent::Builder
        include ForestAdminAgent::Services

        def setup_routes
          add_route(
            'forest_scope_invalidation',
            'POST',
            '/scope-cache-invalidation',
            ->(args) { handle_request(args) }
          )

          self
        end

        def handle_request(args)
          build(args)
          rendering_id = args.dig(:params, 'renderingId')
          Permissions.invalidate_rendering_cache(rendering_id.to_s.strip.empty? ? nil : rendering_id)

          { content: nil, status: 204 }
        end
      end
    end
  end
end
