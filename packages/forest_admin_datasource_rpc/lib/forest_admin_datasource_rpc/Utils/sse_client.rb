require 'openssl'
require 'json'
require 'time'
require 'ld-eventsource'

module ForestAdminDatasourceRpc
  module Utils
    class SseClient
      attr_reader :closed

      MAX_BACKOFF_DELAY = 30 # seconds
      INITIAL_BACKOFF_DELAY = 2 # seconds

      def initialize(uri, auth_secret, &on_rpc_stop)
        @uri = uri
        @auth_secret = auth_secret
        @on_rpc_stop = on_rpc_stop
        @client = nil
        @closed = false
        @connection_attempts = 0
        @reconnect_thread = nil
        @connecting = false
      end

      def start
        return if @closed

        attempt_connection
      end

      def close
        return if @closed

        @closed = true
        ForestAdminAgent::Facades::Container.logger&.log('Debug', '[SSE Client] Closing connection')

        # Stop reconnection thread if running
        if @reconnect_thread&.alive?
          @reconnect_thread.kill
          @reconnect_thread = nil
        end

        begin
          @client&.close
        rescue StandardError => e
          ForestAdminAgent::Facades::Container.logger&.log('Debug', "[SSE Client] Error during close: #{e.message}")
        end

        ForestAdminAgent::Facades::Container.logger&.log('Debug', '[SSE Client] Connection closed')
      end

      private

      def attempt_connection
        return if @closed
        return if @connecting

        @connecting = true
        @connection_attempts += 1
        timestamp = Time.now.utc.iso8601(3)
        signature = generate_signature(timestamp)

        headers = {
          'Accept' => 'text/event-stream',
          'X_TIMESTAMP' => timestamp,
          'X_SIGNATURE' => signature
        }

        ForestAdminAgent::Facades::Container.logger&.log(
          'Debug',
          "[SSE Client] Connecting to #{@uri} (attempt ##{@connection_attempts})"
        )

        begin
          # Close existing client if any
          begin
            @client&.close
          rescue StandardError
            # Ignore close errors
          end

          @client = SSE::Client.new(@uri, headers: headers) do |client|
            client.on_event do |event|
              handle_event(event)
            end

            client.on_error do |err|
              handle_error_with_reconnect(err)
            end
          end

          ForestAdminAgent::Facades::Container.logger&.log('Debug', '[SSE Client] Connected successfully')
        rescue StandardError => e
          ForestAdminAgent::Facades::Container.logger&.log(
            'Error',
            "[SSE Client] Failed to connect: #{e.class} - #{e.message}"
          )
          @connecting = false
          schedule_reconnect
        end
      end

      def handle_error_with_reconnect(err)
        # Ignore errors when client is intentionally closed
        return if @closed

        is_auth_error = false
        log_level = 'Warn'

        error_message = case err
                        when SSE::Errors::HTTPStatusError
                          # Extract more details from HTTP errors
                          status = err.respond_to?(:status) ? err.status : 'unknown'
                          body = err.respond_to?(:body) && !err.body.to_s.strip.empty? ? err.body : 'empty response'
                          is_auth_error = status.to_s =~ /^(401|403)$/

                          # Auth errors during reconnection are expected (server shutdown or credentials expiring)
                          log_level = 'Debug' if is_auth_error

                          "HTTP #{status} - #{body}"
                        when EOFError, IOError
                          # Connection lost is expected when server stops
                          log_level = 'Debug'
                          "Connection lost: #{err.class}"
                        when StandardError
                          "#{err.class} - #{err.message}"
                        else
                          err.to_s
                        end

        ForestAdminAgent::Facades::Container.logger&.log(log_level, "[SSE Client] Error: #{error_message}")

        # Close client immediately to prevent ld-eventsource from reconnecting with stale credentials
        begin
          @client&.close
        rescue StandardError
          # Ignore close errors
        end

        # Reset connecting flag and schedule reconnection
        @connecting = false

        # For auth errors, increase attempt count to get longer backoff
        @connection_attempts += 2 if is_auth_error

        schedule_reconnect
      end

      def schedule_reconnect
        return if @closed
        return if @reconnect_thread&.alive?

        @reconnect_thread = Thread.new do
          delay = calculate_backoff_delay
          ForestAdminAgent::Facades::Container.logger&.log(
            'Debug',
            "[SSE Client] Reconnecting in #{delay} seconds..."
          )
          sleep(delay)
          attempt_connection unless @closed
        end
      end

      def calculate_backoff_delay
        # Exponential backoff: 1, 2, 4, 8, 16, 30, 30, ...
        delay = INITIAL_BACKOFF_DELAY * (2**[@connection_attempts - 1, 0].max)
        [delay, MAX_BACKOFF_DELAY].min
      end

      def handle_event(event)
        type = event.type.to_s.strip
        data = event.data.to_s.strip

        case type
        when 'heartbeat'
          if @connecting
            @connecting = false
            @connection_attempts = 0
            ForestAdminAgent::Facades::Container.logger&.log('Debug', '[SSE Client] Connection stable')
          end
        when 'RpcServerStop'
          ForestAdminAgent::Facades::Container.logger&.log('Debug', '[SSE Client] RpcServerStop received')
          handle_rpc_stop
        else
          ForestAdminAgent::Facades::Container.logger&.log(
            'Debug',
            "[SSE Client] Unknown event: #{type} with payload: #{data}"
          )
        end
      rescue StandardError => e
        ForestAdminAgent::Facades::Container.logger&.log(
          'Error',
          "[SSE Client] Error handling event: #{e.class} - #{e.message}"
        )
      end

      def handle_rpc_stop
        @on_rpc_stop&.call
      rescue StandardError => e
        ForestAdminAgent::Facades::Container.logger&.log(
          'Error',
          "[SSE Client] Error in RPC stop callback: #{e.class} - #{e.message}"
        )
      end

      def generate_signature(timestamp)
        OpenSSL::HMAC.hexdigest('SHA256', @auth_secret, timestamp)
      end
    end
  end
end
