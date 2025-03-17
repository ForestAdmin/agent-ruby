ForestAdminRpcAgent::Engine.routes.draw do
  route_classes = ForestAdminRpcAgent::Routes.constants.reject { |route| route.to_s == 'BaseRoute' }

  route_classes.each do |route|
    route_class = ForestAdminRpcAgent::Routes.const_get(route)

    if route_class.respond_to?(:registered)
      route_class.registered(self)
    else
      Rails.logger.warn "Skipping route: #{route_class} (does not respond to :registered)"
    end
  end
end
