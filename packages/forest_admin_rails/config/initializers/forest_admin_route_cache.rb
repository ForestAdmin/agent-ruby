# Route caching lifecycle management for ForestAdmin routes
#
# Route caching is ENABLED by default in all environments for optimal performance.
# This provides significant performance improvements by avoiding expensive route
# recomputation on every request.
#
# To disable route caching (not recommended), add to your configuration:
#   ForestAdminAgent::Agent.new options do |builder|
#     builder.setup(
#       # ... other options
#       disable_route_cache: true  # Disables route caching
#     )
#   end
#
# When caching is ENABLED (default):
#   - Routes are precomputed once during initialization
#   - Routes remain frozen for the entire application lifetime
#   - Maximum performance: expensive computation happens only once at startup
#
# When caching is DISABLED:
#   - Routes are computed fresh on every access
#   - Performance degradation: ~50-200ms overhead per route definition evaluation
#   - Only recommended for debugging route generation issues
#
# The guard check (if defined?) ensures this initializer is safe to load even if
# ForestAdminAgent is not available, preventing load-time errors.

if defined?(ForestAdminAgent::Http::Router)
  # Check if caching is disabled via configuration
  cache_disabled = ForestAdminAgent::Http::Router.cache_disabled?

  if cache_disabled
    Rails.logger.warn('[ForestAdmin] Route caching is DISABLED - this will impact performance')
    Rails.logger.warn('[ForestAdmin] To enable caching, remove disable_route_cache: true from configuration')
  else
    # Precompute routes once after initialization for all environments
    Rails.application.config.after_initialize do
      start_time = Time.now
      routes = ForestAdminAgent::Http::Router.cached_routes
      elapsed = ((Time.now - start_time) * 1000).round(2)

      Rails.logger.info(
        "[ForestAdmin] Successfully pre-cached #{routes.size} routes in #{elapsed}ms"
      )
    rescue StandardError => e
      Rails.logger.error(
        "[ForestAdmin] CRITICAL: Failed to pre-cache routes: #{e.class} - #{e.message}"
      )
      Rails.logger.error(e.backtrace.first(10).join("\n"))

      raise e if Rails.env.production?

      Rails.logger.warn(
        '[ForestAdmin] Routes will be computed on first request (performance degradation)'
      )
    end
  end
end
