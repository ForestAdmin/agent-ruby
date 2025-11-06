ForestAdminRails::Engine.routes.draw do
  next if defined?(Rake) && Rake.respond_to?(:application) && Rake.application&.top_level_tasks&.any?

  scope '/forest' do
    # Use cached_routes to avoid recomputing routes during Rails route initialization
    ForestAdminAgent::Http::Router.cached_routes.each do |name, agent_route|
      match agent_route[:uri],
            defaults: { format: agent_route[:format] },
            to: 'forest#index',
            via: agent_route[:method],
            as: name,
            route_alias: name,
            constraints: { id: /[a-zA-Z0-9\.\-]*+/ }
    end
  rescue StandardError => e
    if defined?(Rails) && Rails.logger
      Rails.logger.error("[ForestAdmin] CRITICAL: Failed to initialize routes: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
    end
    raise e
  end
end
