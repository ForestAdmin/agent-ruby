# Manage route caching for ForestAdmin routes
# - In development: Reset cache on each code reload to pick up changes
# - In production: Compute once after initialization for optimal performance

if defined?(ForestAdminAgent::Http::Router)
  if Rails.env.development?
    # Recompute cached_routes on each code reload so changes are picked up automatically
    Rails.application.config.to_prepare do
      ForestAdminAgent::Http::Router.reset_cached_routes!
    end
  else
    # In production/test, precompute routes after initialization
    Rails.application.config.after_initialize do
      ForestAdminAgent::Http::Router.cached_routes
    end
  end
end
