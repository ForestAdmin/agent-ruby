module ForestAdminRails
  class ForestController < ActionController::Base
    include ForestAdminAgent::Http::ErrorHandling

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
      if data[:content].is_a?(Hash)
        if data.dig(:content, :type) == 'File'
          return send_data data[:content][:stream], filename: data[:content][:name], type: data[:content][:mime_type],
                                                    disposition: 'attachment'
        end

        if data.dig(:content, :headers)
          response.headers.merge!(data[:content][:headers] || {})
          data[:content].delete(:headers)
        end
      end

      respond_to do |format|
        format.json { render json: data[:content], status: data[:status] || data[:content][:status] || 200 }
        format.csv { render plain: data[:content][:export], status: 200, filename: data[:filename] }
      end
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
              detail: get_error_message(exception),
              status: exception.try(:status)
            }
          ]
        }

        data[:errors][0][:data] = exception.try(:data)
      end

      unless ForestAdminAgent::Facades::Container.cache(:is_production)
        ForestAdminAgent::Facades::Container.logger.log('Debug', exception.full_message)
      end

      render json: data, status: exception.try(:status)
    end
  end
end
