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
      if data.dig(:content, :type) == 'File'
        return send_data data[:content][:stream], filename: data[:content][:name], type: data[:content][:mime_type],
                                                  disposition: 'attachment'
      end

      response.headers.merge!(data[:content][:headers] || {})
      data[:content].delete(:headers)

      render json: data[:content], head: headers, status: data[:status] || data[:content][:status] || 200
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
              status: exception.try(:status)
            }
          ]
        }

        data[:errors][0][:data] = exception.try(:data)

        # TODO: IMPLEMENT LOGGING
        # if Facades::Container.cache(:is_production)
        # end
      end

      render json: data, status: exception.try(:status)
    end
  end
end
