module ForestAdminRails
  class ForestController < ActionController::Base
    skip_forgery_protection

    def index
      if ForestAdminAgent::Http::Router.routes.key? params['route_alias']
        route = ForestAdminAgent::Http::Router.routes[params['route_alias']]

        begin
          forest_response route[:closure].call({ params: params.to_unsafe_h, headers: request.headers.to_h })
        rescue StandardError => e
          exception_handler e
        end
      else
        render json: { error: 'Route not found' }, status: 404
      end
    end

    def forest_response(data = {})
      render json: data[:content], status: data[:status] || 200
    end

    def exception_handler(exception)
      if exception.is_a? ForestAdminAgent::Http::Exceptions::AuthenticationOpenIdClient
        data = {
          error: exception.error,
          error_description: exception.error_description,
          state: exception.state
        }
      else
        data = {
          errors: [
            {
              name: exception.name,
              detail: exception.message,
              status: exception.status
            }
          ]
        }

        data[:errors][0][:data] = exception.data if exception.defined? :data

        # TODO: IMPLEMENT LOGGING
        # if Facades::Container.cache(:is_production)
        # end
      end

      render json: data, status: exception.status
    end
  end
end
