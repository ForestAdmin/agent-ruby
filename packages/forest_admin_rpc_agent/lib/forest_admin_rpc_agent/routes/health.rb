require 'json'

module ForestAdminRpcAgent
  module Routes
    class Health
      def initialize(url = 'health', method = 'get', name = 'rpc_health')
        @url = url
        @method = method
        @name = name
      end

      def registered(app)
        if defined?(Sinatra) && (app == Sinatra::Base || app.ancestors.include?(Sinatra::Base))
          register_sinatra(app)
        elsif defined?(Rails) && app.is_a?(ActionDispatch::Routing::Mapper)
          register_rails(app)
        else
          raise NotImplementedError,
                "Unsupported application type: #{app.class}. #{self} works with Sinatra::Base or ActionDispatch::Routing::Mapper."
        end
      end

      def register_sinatra(app)
        app.send(@method.to_sym, "/#{@url}") do
          auth_middleware = ForestAdminRpcAgent::Middleware::Authentication.new(->(_env) { [200, {}, ['OK']] })
          status, headers, response = auth_middleware.call(env)

          halt status, headers, response if status != 200

          content_type 'application/json'

          ForestAdminRpcAgent::Facades::Container.logger&.log('Debug', '[Health] Health check request received')

          response_body = {
            status: 'ok',
            version: ForestAdminRpcAgent::VERSION
          }

          JSON.generate(response_body)
        end
      end

      def register_rails(router)
        handler = proc do |hash|
          request = ActionDispatch::Request.new(hash)
          auth_middleware = ForestAdminRpcAgent::Middleware::Authentication.new(->(_env) { [200, {}, ['OK']] })
          status, headers, response = auth_middleware.call(request.env)

          if status == 200
            ForestAdminRpcAgent::Facades::Container.logger&.log('Debug', '[Health] Health check request received')

            response_body = {
              status: 'ok',
              version: ForestAdminRpcAgent::VERSION
            }

            headers = { 'Content-Type' => 'application/json' }
            body = [JSON.generate(response_body)]

            [status, headers, body]
          else
            [status, headers, response]
          end
        end

        router.match @url,
                     defaults: { format: 'json' },
                     to: handler,
                     via: @method,
                     as: @name,
                     route_alias: @name
      end
    end
  end
end
