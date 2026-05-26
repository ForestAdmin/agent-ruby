module ForestAdminRpcAgent
  module Routes
    class BaseRoute
      def initialize(url, method, name)
        @url = url
        @method = method
        @name = name
      end

      def registered(app)
        if defined?(Rails) && app.is_a?(ActionDispatch::Routing::Mapper)
          register_rails(app)
        elsif defined?(Sinatra) && app.is_a?(Class) && (app == Sinatra::Base || app.ancestors.include?(Sinatra::Base))
          register_sinatra(app)
        else
          raise NotImplementedError,
                "Unsupported application type: #{app.class}. #{self} works with Sinatra::Base or ActionDispatch::Routing::Mapper."
        end
      end

      def register_sinatra(app)
        app.send(@method.to_sym, @url) do
          result = handle_request({ params: params, request: request })

          if result.is_a?(Hash) && result.key?(:status)
            status result[:status]
            # Set custom headers if provided
            result[:headers]&.each { |key, value| headers[key] = value }
            if result[:content].nil?
              ''
            elsif result[:raw]
              result[:content].to_s
            else
              serialize_response(result[:content])
            end
          else
            serialize_response(result)
          end
        end
      end

      def register_rails(router)
        handler = proc do |hash|
          request = ActionDispatch::Request.new(hash)

          # Skip authentication for health check (root path)
          if @url == '/'
            params = extract_request_params(request)
            result = handle_request({ params: params, caller: nil, request: request })
            build_rails_response(result)
          else
            auth_middleware = ForestAdminRpcAgent::Middleware::Authentication.new(->(_env) { [200, {}, ['OK']] })
            status, headers, response = auth_middleware.call(request.env)

            if status == 200
              params = extract_request_params(request)
              result = handle_request({ params: params, caller: headers[:caller], request: request })
              build_rails_response(result)
            else
              [status, headers, response]
            end
          end
        end

        router.match @url,
                     defaults: { format: 'json' },
                     to: handler,
                     via: @method,
                     as: @name,
                     route_alias: @name
      end

      def build_rails_response(result)
        if result.is_a?(Hash) && result.key?(:status)
          response_headers = { 'Content-Type' => 'application/json' }
          response_headers.merge!(result[:headers]) if result[:headers]
          body = if result[:content].nil?
                   ''
                 elsif result[:raw]
                   result[:content].to_s
                 else
                   serialize_response(result[:content])
                 end
          [result[:status], response_headers, [body]]
        else
          [200, { 'Content-Type' => 'application/json' }, [serialize_response(result)]]
        end
      end

      protected

      def get_collection_safe(datasource, collection_name)
        datasource.get_collection(collection_name)
      rescue ForestAdminDatasourceToolkit::Exceptions::ForestException => e
        raise ForestAdminAgent::Http::Exceptions::NotFoundError, e.message if e.message.include?('not found')

        raise
      end

      private

      # Merge path params (e.g. :collection_name from the URL) with query and body params so
      # consumers that don't duplicate `collection_name` in the body (the Node datasource-rpc)
      # still resolve the route correctly.
      def extract_request_params(request)
        request.path_parameters
               .except(:controller, :action, :format)
               .merge(request.query_parameters)
               .merge(request.request_parameters)
               .with_indifferent_access
      end

      def serialize_response(result)
        return result if result.is_a?(String) && (result.start_with?('{', '['))

        result.to_json
      end
    end
  end
end
