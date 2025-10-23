require 'openid_connect'

module ForestAdminRails
  class ForestController < ActionController::Base
    include ForestAdminAgent::Http::ErrorHandling

    skip_forgery_protection

    def index
      if ForestAdminAgent::Http::Router.cached_routes.key? params['route_alias']
        route = ForestAdminAgent::Http::Router.cached_routes[params['route_alias']]

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
        # Handle streaming responses (NEW)
        return handle_streaming_response(data) if data.dig(:content, :type) == 'Stream'

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

    private

    # Handle streaming response (enumerator-based)
    def handle_streaming_response(data)
      enumerator = data[:content][:enumerator]
      headers = data[:content][:headers] || {}

      # Merge headers
      response.headers.merge!(headers)

      # Set response status
      response.status = data[:status] || 200

      # Stream the enumerator
      # Rails will automatically use chunked transfer encoding
      self.response_body = enumerator
    end

    def exception_handler(exception)
      # Translate BusinessError to HttpError and get all error information
      error_info = translate_error(exception)

      # Add custom headers to the response
      response.headers.merge!(error_info[:headers]) if error_info[:headers].any?

      data = case exception
             when ForestAdminAgent::Http::Exceptions::AuthenticationOpenIdClient,
               OpenIDConnect::Exception
               {
                 error: exception.message,
                 error_description: exception.response,
                 state: exception.status
               }
             else
               {
                 errors: [
                   {
                     name: error_info[:name],
                     detail: error_info[:message],
                     status: error_info[:status],
                     meta: error_info[:meta].presence,
                     data: exception.try(:data)
                   }.compact
                 ]
               }
             end

      unless ForestAdminAgent::Facades::Container.cache(:is_production)
        ForestAdminAgent::Facades::Container.logger.log('Error', exception.full_message)
      end

      render json: data, status: error_info[:status]
    end
  end
end
