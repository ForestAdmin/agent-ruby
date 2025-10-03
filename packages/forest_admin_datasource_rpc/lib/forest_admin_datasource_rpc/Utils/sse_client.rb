require 'openssl'
require 'json'
require 'time'
require 'ld-eventsource'

module ForestAdminDatasourceRpc
  module Utils
    class SseClient
      attr_reader :closed

      def initialize(uri, auth_secret, &on_rpc_stop)
        @uri = uri
        @auth_secret = auth_secret
        @on_rpc_stop = on_rpc_stop
        @client = nil
        @closed = false
        @connection_attempts = 0
      end

      def start
        return if @closed

        timestamp = Time.now.utc.iso8601(3)
        signature = generate_signature(timestamp)

        headers = {
          'Accept' => 'text/event-stream',
          'X_TIMESTAMP' => timestamp,
          'X_SIGNATURE' => signature
        }

        @connection_attempts += 1
        ForestAdminRpcAgent::Facades::Container.logger&.log(
          'Debug',
          "[SSE Client] Connecting to #{@uri} (attempt ##{@connection_attempts})"
        )

        begin
          @client = SSE::Client.new(@uri, headers: headers) do |client|
            client.on_event do |event|
              handle_event(event)
            end

            client.on_error do |err|
              handle_error(err)
            end
          end

          ForestAdminRpcAgent::Facades::Container.logger&.log('Debug', '[SSE Client] Connected successfully')
        rescue StandardError => e
          ForestAdminRpcAgent::Facades::Container.logger&.log(
            'Error',
            "[SSE Client] Failed to connect: #{e.class} - #{e.message}"
          )
          raise
        end
      end

      def close
        return if @closed

        @closed = true
        ForestAdminRpcAgent::Facades::Container.logger&.log('Debug', '[SSE Client] Closing connection')

        begin
          @client&.close
        rescue StandardError => e
          ForestAdminRpcAgent::Facades::Container.logger&.log('Debug',
                                                              "[SSE Client] Error during close: #{e.message}")
        end

        ForestAdminRpcAgent::Facades::Container.logger&.log('Debug', '[SSE Client] Connection closed')
      end

      private

      def handle_event(event)
        type = event.type.to_s.strip
        data = event.data.to_s.strip

        case type
        when 'heartbeat'
          # Heartbeat received - connection is alive
        when 'RpcServerStop'
          ForestAdminRpcAgent::Facades::Container.logger&.log('Debug', '[SSE Client] RpcServerStop received')
          handle_rpc_stop
        else
          ForestAdminRpcAgent::Facades::Container.logger&.log(
            'Debug',
            "[SSE Client] Unknown event: #{type} with payload: #{data}"
          )
        end
      rescue StandardError => e
        ForestAdminRpcAgent::Facades::Container.logger&.log(
          'Error',
          "[SSE Client] Error handling event: #{e.class} - #{e.message}"
        )
      end

      def handle_error(err)
        # Ignore errors when client is intentionally closed
        return if @closed

        error_message = case err
                        when EOFError, IOError
                          "Connection lost: #{err.class}"
                        when StandardError
                          "#{err.class} - #{err.message}"
                        else
                          err.to_s
                        end

        ForestAdminRpcAgent::Facades::Container.logger&.log('Warn', "[SSE Client] Error: #{error_message}")
      end

      def handle_rpc_stop
        @on_rpc_stop&.call
      rescue StandardError => e
        ForestAdminRpcAgent::Facades::Container.logger&.log(
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
