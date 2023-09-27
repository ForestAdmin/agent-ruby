module ForestAdminRails
  class ForestController < ActionController::Base
    skip_forgery_protection

    def index
      if ForestAdminAgent::Http::Router.routes.key? params['route_alias']
        route = ForestAdminAgent::Http::Router.routes[params['route_alias']]

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
