require 'openssl'
require 'json'
require 'time'

module ForestAdminDatasourceRpc
  module Utils
    # rubocop:disable Metrics/ClassLength
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
          while remaining.positive? && !@closed
            sleep([remaining, 1].min)
            remaining -= 1
          end
        end
      end

      def check_schema
        @connection_attempts += 1
        log_checking_schema

        result = @rpc_client.fetch_schema('/forest/rpc-schema', if_none_match: @cached_etag)
        handle_schema_result(result)
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
        log_connection_error(e)
      rescue ForestAdminAgent::Http::Exceptions::AuthenticationOpenIdClient => e
        log_authentication_error(e)
      rescue StandardError => e
        log_unexpected_error(e)
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

      def log_checking_schema
        ForestAdminAgent::Facades::Container.logger&.log(
          'Debug',
          "[Schema Polling] Checking schema from #{@uri}/forest/rpc-schema (attempt ##{@connection_attempts})"
        )
      end

      def handle_schema_result(result)
        if result == RpcClient::NotModified
          handle_schema_unchanged
        else
          handle_schema_changed(result)
        end
      end

      def handle_schema_unchanged
        ForestAdminAgent::Facades::Container.logger&.log('Debug', '[Schema Polling] Schema unchanged (HTTP 304)')
        @connection_attempts = 0
      end

      def handle_schema_changed(result)
        new_etag = result.etag
        @cached_etag.nil? ? handle_initial_schema(new_etag) : handle_schema_update(result.body, new_etag)
        @connection_attempts = 0
      end

      def handle_initial_schema(etag)
        @cached_etag = etag
        ForestAdminAgent::Facades::Container.logger&.log('Debug', '[Schema Polling] Initial schema loaded')
      end

      def handle_schema_update(schema, etag)
        @cached_etag = etag
        ForestAdminAgent::Facades::Container.logger&.log(
          'Info',
          '[Schema Polling] Schema changed detected, triggering reload callback'
        )
        trigger_schema_change_callback(schema)
      end

      def log_connection_error(error)
        ForestAdminAgent::Facades::Container.logger&.log(
          'Warn',
          "[Schema Polling] Connection error: #{error.class} - #{error.message}"
        )
      end

      def log_authentication_error(error)
        ForestAdminAgent::Facades::Container.logger&.log(
          'Error',
          "[Schema Polling] Authentication error: #{error.message}"
        )
      end

      def log_unexpected_error(error)
        ForestAdminAgent::Facades::Container.logger&.log(
          'Error',
          "[Schema Polling] Unexpected error: #{error.class} - #{error.message}"
        )
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
    # rubocop:enable Metrics/ClassLength
  end
end
