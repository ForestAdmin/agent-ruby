# Route pre-caching has been moved to engine.rb after agent.build() completes
#
# This initializer is kept for informational purposes only
if defined?(ForestAdminAgent::Http::Router)
  cache_disabled = ForestAdminAgent::Http::Router.cache_disabled?

  if cache_disabled
    Rails.logger.warn('[ForestAdmin] Route caching is DISABLED - this will impact performance')
    Rails.logger.warn('[ForestAdmin] To enable caching, remove disable_route_cache: true from configuration')
  end
end
