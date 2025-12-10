require 'openssl'
require 'json'
require 'time'

module ForestAdminDatasourceRpc
  module Utils
    class SchemaPollingClient
      attr_reader :closed

      DEFAULT_POLLING_INTERVAL = 600 # seconds (10 minutes)
      MIN_POLLING_INTERVAL = 1 # seconds (minimum safe interval)
      MAX_POLLING_INTERVAL = 3600 # seconds (1 hour max)

      def initialize(uri, auth_secret, options = {}, &on_schema_change)
        @uri = uri
        @auth_secret = auth_secret
        @polling_interval = options[:polling_interval] || DEFAULT_POLLING_INTERVAL
        @on_schema_change = on_schema_change
        @closed = false
        @cached_etag = nil
        @polling_thread = nil
        @mutex = Mutex.new
        @connection_attempts = 0

        # Validate polling interval
        validate_polling_interval!

        # RPC client for schema fetching with ETag support
        @rpc_client = RpcClient.new(@uri, @auth_secret)
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

        ForestAdminAgent::Facades::Container.logger&.log(
          'Info',
          "[Schema Polling] Polling started (interval: #{@polling_interval}s)"
        )
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

        ForestAdminAgent::Facades::Container.logger&.log(
          'Debug',
          "[Schema Polling] Checking schema from #{@uri}/forest/rpc-schema (attempt ##{@connection_attempts})"
        )

        # Fetch schema with ETag support (sends If-None-Match header if we have a cached ETag)
        result = @rpc_client.fetch_schema('/forest/rpc-schema', if_none_match: @cached_etag)

        # Check if schema has changed (NotModified means 304 response)
        if result == RpcClient::NotModified
          ForestAdminAgent::Facades::Container.logger&.log(
            'Debug',
            '[Schema Polling] Schema unchanged (HTTP 304)'
          )
          @connection_attempts = 0
        else
          # Schema changed or first poll
          schema = result.body
          new_etag = result.etag

          if @cached_etag.nil?
            # First poll - just store the ETag
            @cached_etag = new_etag
            ForestAdminAgent::Facades::Container.logger&.log(
              'Debug',
              '[Schema Polling] Initial schema loaded'
            )
            @connection_attempts = 0
          else
            # Schema changed - trigger callback
            ForestAdminAgent::Facades::Container.logger&.log(
              'Info',
              '[Schema Polling] Schema changed detected, triggering reload callback'
            )
            @cached_etag = new_etag
            @connection_attempts = 0
            trigger_schema_change_callback(schema)
          end
        end
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
        ForestAdminAgent::Facades::Container.logger&.log(
          'Warn',
          "[Schema Polling] Connection error: #{e.class} - #{e.message}"
        )
      rescue ForestAdminAgent::Http::Exceptions::AuthenticationOpenIdClient => e
        ForestAdminAgent::Facades::Container.logger&.log(
          'Error',
          "[Schema Polling] Authentication error: #{e.message}"
        )
      rescue StandardError => e
        ForestAdminAgent::Facades::Container.logger&.log(
          'Error',
          "[Schema Polling] Unexpected error: #{e.class} - #{e.message}"
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

      def validate_polling_interval!
        if @polling_interval < MIN_POLLING_INTERVAL
          raise ArgumentError,
                "Schema polling interval too short: #{@polling_interval}s (minimum: #{MIN_POLLING_INTERVAL}s)"
        elsif @polling_interval > MAX_POLLING_INTERVAL
          raise ArgumentError,
                "Schema polling interval too long: #{@polling_interval}s (maximum: #{MAX_POLLING_INTERVAL}s)"
        end
      end
    end
  end
end
