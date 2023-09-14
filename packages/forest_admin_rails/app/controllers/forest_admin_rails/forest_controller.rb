module ForestAdminRails
  class ForestController < ActionController::Base
    def index
      route_alias = request.routes.named_routes.helper_names.first.delete_suffix('_path')
      if ForestAdminAgent::Http::Router.routes.key? route_alias
        route = ForestAdminAgent::Http::Router.routes[route_alias]

        forest_response route[:closure].call(params)
      else
        render json: { error: 'Route not found' }, status: 404
      end
    end

    def forest_response(data = {})
      render json: data[:content], status: data[:status] || 200
    end
  end
end
