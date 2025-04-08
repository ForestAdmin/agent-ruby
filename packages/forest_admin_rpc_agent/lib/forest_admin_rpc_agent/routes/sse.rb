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
                'Unsupported application type'
        end
      end

      def register_sinatra(_app)
        # TODO
      end

      def register_rails2(router)
        sse_route = self
        handler = proc do |hash|
          ActionDispatch::Request.new(hash)

          # auth_middleware = ForestAdminRpcAgent::Middleware::Authentication.new(->(_env) { [200, {}, ['OK']] })
          # status, headers, response = auth_middleware.call(request.env)

          # if status == 200
          streaming_response = ActionDispatch::Response.new
          streaming_response.headers['Content-Type'] = 'text/event-stream'
          streaming_response.headers['Cache-Control'] = 'no-cache'
          streaming_response.headers['Connection'] = 'keep-alive'

          Thread.new do
            sse_route.stream_events(streaming_response.stream)
          rescue StandardError => e
            ForestAdminAgent::Facades::Container.logger.log('debug', "Error in SSE stream: #{e.message}")
          ensure
            streaming_response.stream.close
          end

          [200, streaming_response.headers, streaming_response]
          # else
          #   [status, headers, response]
          # end
        end

        router.match @url,
                     defaults: { format: 'event-stream' },
                     to: handler,
                     via: @method,
                     as: @name,
                     route_alias: @name
      end

      def stream_events(stream)
        puts '[SSE] start streaming'
        sse = SseStreamer.new(stream)
        sse.write('ready', event: 'ready')
        begin
          while connected?(stream)
            sse.write('', event: 'heartbeat')
            sleep 1
          end
        rescue IOError
          # Client disconnected
        ensure
          sse.write({ event: 'RpcServerStop' }, event: 'RpcServerStop')
          sse.close
        end
      end

      def connected?(stream)
        puts '[SSE] check connection'
        !stream.closed?
      rescue IOError
        false
      end
    end
  end
end
