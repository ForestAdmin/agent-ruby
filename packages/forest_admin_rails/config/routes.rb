ForestAdminRails::Engine.routes.draw do
  scope '/forest' do
    # Use cached_routes to avoid recomputing routes during Rails route initialization
    # Without caching, routes would be recomputed each time this block is evaluated
    # (e.g., during code reloads in development or when routes are inspected)
    ForestAdminAgent::Http::Router.cached_routes.each do |name, agent_route|
      match agent_route[:uri],
            defaults: { format: agent_route[:format] },
            to: 'forest#index',
            via: agent_route[:method],
            as: name,
            route_alias: name,
            constraints: { id: /[a-zA-Z0-9\.]*+/ }
    end
  rescue StandardError => e
    # Log with full context for debugging - route initialization errors should be visible
    if defined?(Rails) && Rails.logger
      Rails.logger.error("[ForestAdmin] CRITICAL: Failed to initialize routes: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
    end
    # Re-raise to fail application startup - routes are essential infrastructure
    raise e
  end
end
