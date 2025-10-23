if defined?(ForestAdminAgent::Http::Router)
  cache_disabled = ForestAdminAgent::Http::Router.cache_disabled?

  if cache_disabled
    Rails.logger.warn('[ForestAdmin] Route caching is DISABLED - this will impact performance')
    Rails.logger.warn('[ForestAdmin] To enable caching, remove disable_route_cache: true from configuration')
  else
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
