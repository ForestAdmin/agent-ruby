require 'openssl'
require 'json'
require 'time'
require 'faraday'
require 'digest'

module ForestAdminDatasourceRpc
  module Utils
    class SchemaPollingClient
      attr_reader :closed

      DEFAULT_POLLING_INTERVAL = 600 # seconds (10 minutes)

      def initialize(uri, auth_secret, options = {}, &on_schema_change)
        @uri = uri
        @auth_secret = auth_secret
        @polling_interval = options[:polling_interval] || DEFAULT_POLLING_INTERVAL
        @on_schema_change = on_schema_change
        @closed = false
        @last_schema_hash = nil
        @polling_thread = nil
        @mutex = Mutex.new
        @connection_attempts = 0

        # HTTP client with reasonable timeouts
        @http_client = Faraday.new do |conn|
          conn.options.timeout = 10
          conn.options.open_timeout = 10
          conn.adapter Faraday.default_adapter
        end
      end

      def start
        return if @closed

        @mutex.synchronize do
          return if @polling_thread&.alive?

          @polling_thread = Thread.new do
            polling_loop
          rescue StandardError => e
            ForestAdminAgent::Facades::Container.logger&.log(
              'Error',
              "[Schema Polling] Unexpected error in polling loop: #{e.class} - #{e.message}"
            )
          end
        end

        ForestAdminAgent::Facades::Container.logger&.log('Debug', '[Schema Polling] Polling started')
      end

      def stop
        return if @closed

        @closed = true
        ForestAdminAgent::Facades::Container.logger&.log('Debug', '[Schema Polling] Stopping polling')

        @mutex.synchronize do
          if @polling_thread&.alive?
            @polling_thread.kill
            @polling_thread = nil
          end
        end

        ForestAdminAgent::Facades::Container.logger&.log('Debug', '[Schema Polling] Polling stopped')
      end

      private

      def polling_loop
        ForestAdminAgent::Facades::Container.logger&.log(
          'Debug',
          "[Schema Polling] Starting polling loop (interval: #{@polling_interval}s)"
        )

        loop do
          break if @closed

          begin
            check_schema
          rescue StandardError => e
            handle_error(e)
          end

          # Sleep with interrupt check (check every second for early termination)
          remaining = @polling_interval
          while remaining > 0 && !@closed
            sleep([remaining, 1].min)
            remaining -= 1
          end
        end
      end

      def check_schema
        @connection_attempts += 1
        timestamp = Time.now.utc.iso8601(3)
        signature = generate_signature(timestamp)

        headers = {
          'X_TIMESTAMP' => timestamp,
          'X_SIGNATURE' => signature
        }

        ForestAdminAgent::Facades::Container.logger&.log(
          'Debug',
          "[Schema Polling] Fetching schema from #{@uri}/forest/rpc-schema (attempt ##{@connection_attempts})"
        )

        response = @http_client.get("#{@uri}/forest/rpc-schema", nil, headers)

        if response.success?
          schema = JSON.parse(response.body, symbolize_names: true)
          new_hash = Digest::SHA1.hexdigest(schema.to_h.to_s)

          if @last_schema_hash.nil?
            # First poll - just store the hash
            @last_schema_hash = new_hash
            ForestAdminAgent::Facades::Container.logger&.log(
              'Debug',
              '[Schema Polling] Initial schema hash stored'
            )
            @connection_attempts = 0
          elsif @last_schema_hash != new_hash
            # Schema changed - trigger callback
            ForestAdminAgent::Facades::Container.logger&.log(
              'Info',
              '[Schema Polling] Schema changed detected, triggering reload callback'
            )
            @last_schema_hash = new_hash
            @connection_attempts = 0
            trigger_schema_change_callback(schema)
          else
            # Schema unchanged
            ForestAdminAgent::Facades::Container.logger&.log(
              'Debug',
              '[Schema Polling] Schema unchanged'
            )
            @connection_attempts = 0
          end
        else
          ForestAdminAgent::Facades::Container.logger&.log(
            'Warn',
            "[Schema Polling] HTTP #{response.status}: #{response.body}"
          )
        end
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
        ForestAdminAgent::Facades::Container.logger&.log(
          'Warn',
          "[Schema Polling] Connection error: #{e.class} - #{e.message}"
        )
      rescue JSON::ParserError => e
        ForestAdminAgent::Facades::Container.logger&.log(
          'Error',
          "[Schema Polling] Invalid JSON response: #{e.message}"
        )
      end

      def handle_error(error)
        ForestAdminAgent::Facades::Container.logger&.log(
          'Error',
          "[Schema Polling] Error during schema check: #{error.class} - #{error.message}"
        )
      end

      def trigger_schema_change_callback(schema)
        return unless @on_schema_change

        begin
          @on_schema_change.call(schema)
        rescue StandardError => e
          ForestAdminAgent::Facades::Container.logger&.log(
            'Error',
            "[Schema Polling] Error in schema change callback: #{e.class} - #{e.message}"
          )
        end
      end

      def generate_signature(timestamp)
        OpenSSL::HMAC.hexdigest('SHA256', @auth_secret, timestamp)
      end
    end
  end
end
