module ForestAdminRpcAgent
  module Routes
    class BaseRoute
      def initialize(url, method, name)
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
        app.send(@method.to_sym, @url) do
          handle_request(params)
        end
      end

      def register_rails(router)
        handler = proc do |hash|
          request = ActionDispatch::Request.new(hash)

          auth_middleware = ForestAdminRpcAgent::Middleware::Authentication.new(->(_env) { [200, {}, ['OK']] })
          status, headers, response = auth_middleware.call(request.env)

          if status == 200
            params = request.query_parameters.merge(request.request_parameters)

            [200, { 'Content-Type' => 'application/json' }, [handle_request({ params: params })]]
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
