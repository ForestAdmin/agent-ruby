ForestadminRails::Engine.routes.draw do
  # TODO: replace by AgentRouter.routes
  agent_router_routes = { route1: { method: ['GET'], uri: '/aa' },
                          route2: { method: ['GET'], uri: '/aa/:id' } }
  agent_router_routes.each do |name, agent_route|
    path = ForestadminRails.config[:prefix] + agent_route[:uri]
    match path, to: 'forest#index', via: agent_route[:method].map(&:upcase), as: name
  end
end
