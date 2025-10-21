ForestAdminRails::Engine.routes.draw do
  Rails.error.handle(ForestAdminDatasourceToolkit::Exceptions::ForestException) do
    scope '/forest' do
      # Use cached_routes to avoid recomputing routes on every request
      ForestAdminAgent::Http::Router.cached_routes.each do |name, agent_route|
        match agent_route[:uri],
              defaults: { format: agent_route[:format] },
              to: 'forest#index',
              via: agent_route[:method],
              as: name,
              route_alias: name,
              constraints: { id: /[a-zA-Z0-9\.]*+/ }
      end
    end
  end
end
