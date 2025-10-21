# Route caching lifecycle management for ForestAdmin routes
#
# This initializer configures different caching strategies based on environment:
#
# Development Mode (Rails.env.development?):
#   - Calls reset_cached_routes! on every code reload (to_prepare callback)
#   - Ensures route changes are picked up automatically during development
#   - Without this, code reloads would not refresh routes, causing stale route bugs
#   - Trade-off: Routes recomputed on each code change, but this is acceptable for dev
#
# Production/Test Mode:
#   - Precomputes routes once during after_initialize phase
#   - Routes are computed after all Rails initialization is complete
#   - No runtime recomputation - routes remain frozen for entire app lifetime
#   - Maximum performance: expensive computation happens only once at startup
#
# The guard check (if defined?) ensures this initializer is safe to load even if
# ForestAdminAgent is not available, preventing load-time errors.

if defined?(ForestAdminAgent::Http::Router)
  if Rails.env.development?
    # Recompute cached_routes on each code reload so changes are picked up automatically
    Rails.application.config.to_prepare do
      begin
        ForestAdminAgent::Http::Router.reset_cached_routes!
      rescue StandardError => e
        Rails.logger.warn("[ForestAdmin] Failed to reset route cache during development reload: #{e.class} - #{e.message}")
        Rails.logger.warn("Routes will be recomputed on next request")
        # In development, this is recoverable - log and continue
      end
    end
  else
    # In production/test, precompute routes after initialization
    Rails.application.config.after_initialize do
      begin
        start_time = Time.now
        routes = ForestAdminAgent::Http::Router.cached_routes
        elapsed = ((Time.now - start_time) * 1000).round(2)

        Rails.logger.info("[ForestAdmin] Successfully pre-cached #{routes.size} routes in #{elapsed}ms")
      rescue StandardError => e
        Rails.logger.error("[ForestAdmin] CRITICAL: Failed to pre-cache routes: #{e.class} - #{e.message}")
        Rails.logger.error(e.backtrace.first(10).join("\n"))

        if Rails.env.production?
          # In production, route caching failure should fail startup
          raise e
        else
          Rails.logger.warn("[ForestAdmin] Routes will be computed on first request (performance degradation)")
        end
      end
    end
  end
end
