require 'jsonapi-serializers'

module ForestAdminRpcAgent
  module Routes
    class Sse
      DEFAULT_HEARTBEAT_INTERVAL = 1

      def initialize(url = 'rpc/sse', method = 'get', name = 'rpc_sse', heartbeat_interval: DEFAULT_HEARTBEAT_INTERVAL)
        @url = url
        @method = method
        @name = name
        @heartbeat_interval = heartbeat_interval
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
        route_instance = self
        app.send(@method.to_sym, "/#{@url}") do
          auth_middleware = ForestAdminRpcAgent::Middleware::Authentication.new(->(_env) { [200, {}, ['OK']] })
          status, headers, response = auth_middleware.call(env)

          halt status, headers, response if status != 200

          content_type 'text/event-stream'
          headers 'Cache-Control' => 'no-cache',
                  'Connection' => 'keep-alive',
                  'X-Accel-Buffering' => 'no'

          stream(:keep_open) do |out|
            should_continue = true
            server_stopped = false
            stop_proc = proc do
              should_continue = false
              server_stopped = true
            end
            original_handler = trap('INT', stop_proc)

            begin
              streamer = SseStreamer.new(out)

              while should_continue
                streamer.write('', event: 'heartbeat')
                sleep route_instance.instance_variable_get(:@heartbeat_interval)
              end

              # Send RpcServerStop only if server is stopping (not client disconnect)
              if server_stopped
                begin
                  streamer.write({ event: 'RpcServerStop' }, event: 'RpcServerStop')
                  ForestAdminRpcAgent::Facades::Container.logger&.log('Debug', '[SSE] RpcServerStop event sent')
                rescue StandardError => e
                  ForestAdminRpcAgent::Facades::Container.logger&.log('Debug', "[SSE] Error sending stop event: #{e.message}")
                end
              end
            rescue IOError, Errno::EPIPE => e
              # Client disconnected normally
              ForestAdminRpcAgent::Facades::Container.logger&.log('Debug', "[SSE] Client disconnected: #{e.message}")
            ensure
              trap('INT', original_handler)
              out.close if out.respond_to?(:close)
            end
          end
        end
      end

      def register_rails(router)
        route_instance = self
        handler = proc do |hash|
          request = ActionDispatch::Request.new(hash)
          auth_middleware = ForestAdminRpcAgent::Middleware::Authentication.new(->(_env) { [200, {}, ['OK']] })
          status, headers, response = auth_middleware.call(request.env)

          if status == 200
            headers = {
              'Content-Type' => 'text/event-stream',
              'Cache-Control' => 'no-cache',
              'Connection' => 'keep-alive',
              'X-Accel-Buffering' => 'no'
            }

            should_continue = true
            server_stopped = false
            stop_proc = proc do
              should_continue = false
              server_stopped = true
            end
            original_handler = trap('INT', stop_proc)

            body = Enumerator.new do |yielder|
              stream = SseStreamer.new(yielder)

              begin
                ForestAdminRpcAgent::Facades::Container.logger&.log('Debug', '[SSE] Starting stream')

                while should_continue
                  stream.write('', event: 'heartbeat')
                  sleep route_instance.instance_variable_get(:@heartbeat_interval)
                end

                # Send RpcServerStop only if server is stopping (not client disconnect)
                if server_stopped
                  begin
                    stream.write({ event: 'RpcServerStop' }, event: 'RpcServerStop')
                    ForestAdminRpcAgent::Facades::Container.logger&.log('Debug', '[SSE] RpcServerStop event sent')
                  rescue StandardError => e
                    ForestAdminRpcAgent::Facades::Container.logger&.log('Debug', "[SSE] Error sending stop event: #{e.message}")
                  end
                end
              rescue IOError, Errno::EPIPE => e
                # Client disconnected normally
                ForestAdminRpcAgent::Facades::Container.logger&.log('Debug', "[SSE] Client disconnected: #{e.message}")
              rescue StandardError => e
                ForestAdminRpcAgent::Facades::Container.logger&.log('Error', "[SSE] Unexpected error: #{e.message}")
                ForestAdminRpcAgent::Facades::Container.logger&.log('Error', e.backtrace.join("\n"))
              ensure
                trap('INT', original_handler)
                ForestAdminRpcAgent::Facades::Container.logger&.log('Debug', '[SSE] Stream stopped')
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
