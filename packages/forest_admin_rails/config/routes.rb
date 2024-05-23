ForestAdminRails::Engine.routes.draw do
  Rails.error.handle(ForestAdminDatasourceToolkit::Exceptions::ForestException) do
    ForestAdminAgent::Http::Router.routes.each do |name, agent_route|
      match agent_route[:uri], defaults: { format: agent_route[:format] }, to: 'forest#index',
                               via: agent_route[:method], as: name, route_alias: name
    end
  end
end
