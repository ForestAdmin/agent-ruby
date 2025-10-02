ForestAdminRails.configure do |config|
  config.forest_server_url = ENV['FOREST_SERVER_URL']
  config.auth_secret = ENV['FOREST_AUTH_SECRET']
  config.env_secret = ENV['FOREST_ENV_SECRET']
  # config.prefix = ''
  # config.customize_error_message = proc { |_error| '' }
  config.append_schema_path = ENV['FOREST_APPEND_SCHEMA_PATH']
end

Rails.application.config.to_prepare do
  ForestAdminRails::ForestController.class_eval do
    def index
      if ForestAdminAgent::Http::Router.routes.key? params['route_alias']
        route = ForestAdminAgent::Http::Router.routes[params['route_alias']]

        begin
          forest_response route[:closure].call({ params: params.to_unsafe_h, headers: request.headers.to_h })
        rescue ForestAdminDatasourceToolkit::Exceptions::ForestException => e
          if e.message.match?(/Collection .+ not found/)
            Rails.logger.warn "ForestAdmin - #{e.message} - Proxying to forest v1 app"
            proxy_to_forest_v1
          else
            exception_handler(e)
          end
        rescue StandardError => e
          exception_handler(e)
        end
      else
        render json: { error: 'Route not found' }, status: 404
      end
    end

    private

    def proxy_to_forest_v1
      forest_v1_url = ENV.fetch('FOREST_V1_URL', 'http://localhost:3000')
      uri = URI.join(forest_v1_url, request.fullpath)

      http_method = request.method.downcase.to_sym
      headers = extract_proxy_headers

      begin
        response = HTTParty.send(
          http_method,
          uri.to_s,
          headers: headers,
          body: request.body.read,
          follow_redirects: false
        )

        render json: response.body, status: response.code
      rescue StandardError => e
        Rails.logger.error "Failed to proxy to warehouse: #{e.message}"
        render json: {
          errors: [{
                     name: 'ProxyError',
                     detail: "Failed to proxy request to warehouse: #{e.message}",
                     status: 502
                   }]
        }, status: :bad_gateway
      end
    end

    def extract_proxy_headers
      headers = {}
      request.headers.each do |key, value|
        next unless key.start_with?('HTTP_')

        header_name = key.sub('HTTP_', '').split('_').map(&:capitalize).join('-')
        headers[header_name] = value unless %w[Host Version].include?(header_name)
      end
      headers['Content-Type'] = request.content_type if request.content_type
      headers
    end
  end
end