require 'openssl'
require 'json'
require 'time'
require 'ld-eventsource'

module ForestAdminDatasourceRpc
  module Utils
    class SseClient
      def initialize(uri, auth_secret)
        @uri = uri
        @auth_secret = auth_secret
        start
      end

      def start
        timestamp = Time.now.utc.iso8601
        signature = generate_signature(timestamp)

        headers = {
          'Accept' => 'text/event-stream',
          'X_TIMESTAMP' => timestamp,
          'X_SIGNATURE' => signature
        }

        ForestAdminRpcAgent::Facades::Container.logger.log('Debug', "Connecting to SSE at #{@uri}.")

        @client = SSE::Client.new(@uri, headers: headers) do |client|
          Thread.new do
            client.on_event do |event|
              handle_event(event)
            end
          rescue StandardError => e
            puts "[SSE] Connection closed or failed: #{e.class} - #{e.message}"
            close
          end
        end
      end

      def close
        return if @closed

        @closed = true
        @client&.close
        puts '[SSE] Client closed'
      end

      private

      def handle_event(event)
        case event.type.to_s.strip
        when 'heartbeat'
          puts '[SSE] Heartbeat'
        when 'RpcServerStop'
          puts '[SSE] Server requested stop'
          close
        else
          puts "[SSE] Unknown event: #{event.type} with payload: #{event.data}"
        end
      end

      def generate_signature(timestamp)
        OpenSSL::HMAC.hexdigest('SHA256', @auth_secret, timestamp)
      end
    end
  end
end
