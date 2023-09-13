ForestAdminRails::Engine.routes.draw do
  ForestAdminAgent::Http::Router.routes.each do |name, agent_route|
    match agent_route[:uri], to: 'forest#index', via: agent_route[:method], as: name
  end
end
