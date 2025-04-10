require 'jsonapi-serializers'

module ForestAdminRpcAgent
  module Routes
    class Sse
      def initialize(url = 'rpc/sse', method = 'get', name = 'rpc_sse')
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

      def register_sinatra(_app)
        # TODO
      end

      def register_rails(router)
        handler = proc do |hash|
          request = ActionDispatch::Request.new(hash)
          auth_middleware = ForestAdminRpcAgent::Middleware::Authentication.new(->(_env) { [200, {}, ['OK']] })
          status, headers, response = auth_middleware.call(request.env)

          if status == 200
            headers = {
              'Content-Type' => 'text/event-stream',
              'Cache-Control' => 'no-cache',
              'Connection' => 'keep-alive'
            }

            should_continue = true
            # Intercept CTRL+C
            stop_proc = proc { should_continue = false }
            original_handler = trap('INT', stop_proc)

            body = Enumerator.new do |yielder|
              stream = SseStreamer.new(yielder)

              begin
                while should_continue
                  puts '[SSE] heartbeat'
                  stream.write('', event: 'heartbeat')
                  sleep 1
                end
              rescue IOError
                puts '[SSE] disconnected'
                # Client disconnected
              ensure
                trap('INT', original_handler)
                stream.write({ event: 'RpcServerStop' }, event: 'RpcServerStop')
                puts '[SSE] stopped streaming'
                yielder.close if yielder.respond_to?(:close)
              end
            end

            [status, headers, body]
          else
            [status, headers, response]
          end
        end

        router.match @url,
                     defaults: { format: 'event-stream' },
                     to: handler,
                     via: @method,
                     as: @name,
                     route_alias: @name
      end
    end
  end
end
