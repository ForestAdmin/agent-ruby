require 'openssl'
require 'json'
require 'time'
require 'ld-eventsource'

module ForestAdminDatasourceRpc
  module Utils
    class SseClient
      def initialize(uri, auth_secret, &on_rpc_stop)
        @uri = uri
        @auth_secret = auth_secret
        @on_rpc_stop = on_rpc_stop
        @client = nil
        @closed = false
      end

      def start
        return if @closed

        timestamp = Time.now.utc.iso8601
        signature = generate_signature(timestamp)

        headers = {
          'Accept' => 'text/event-stream',
          'X_TIMESTAMP' => timestamp,
          'X_SIGNATURE' => signature
        }

        ForestAdminRpcAgent::Facades::Container.logger.log('Debug', "Connecting to SSE at #{@uri}.")

        @client = SSE::Client.new(@uri, headers: headers) do |client|
          client.on_event do |event|
            handle_event(event)
          end

          client.on_error do |err|
            ForestAdminRpcAgent::Facades::Container.logger.log('Warn', "[SSE] ⚠️ Error: #{err.class} - #{err.message}")
          end
        end
      end

      def close
        return if @closed

        @closed = true
        @client&.close
        # ForestAdminRpcAgent::Facades::Container.logger.log('Debug', '[SSE] Client closed')
      end

      private

      def handle_event(event)
        type = event.type.to_s.strip
        data = event.data.to_s.strip

        case type
        when 'heartbeat'
          # ForestAdminRpcAgent::Facades::Container.logger.log('Debug', '[SSE] Heartbeat')
        when 'RpcServerStop'
          # ForestAdminRpcAgent::Facades::Container.logger.log('Debug', '[SSE] RpcServerStop received')
          @on_rpc_stop&.call
        else
          ForestAdminRpcAgent::Facades::Container.logger.log('Debug',
                                                             "[SSE] Unknown event: #{type} with payload: #{data}")
        end
      end

      def generate_signature(timestamp)
        OpenSSL::HMAC.hexdigest('SHA256', @auth_secret, timestamp)
      end
    end
  end
end
