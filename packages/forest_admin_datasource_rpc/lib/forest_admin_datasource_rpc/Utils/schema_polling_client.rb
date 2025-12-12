require 'openssl'
require 'json'
require 'time'

module ForestAdminDatasourceRpc
  module Utils
    class SchemaPollingClient
      attr_reader :closed, :current_schema

      DEFAULT_POLLING_INTERVAL = 600 # seconds (10 minutes)
      MIN_POLLING_INTERVAL = 1 # seconds (minimum safe interval)
      MAX_POLLING_INTERVAL = 3600 # seconds (1 hour max)

      def initialize(uri, auth_secret, options = {}, previous_schema = nil, &on_schema_change)
        @uri = uri
        @auth_secret = auth_secret
        @polling_interval = options[:polling_interval] || DEFAULT_POLLING_INTERVAL
        @on_schema_change = on_schema_change
        @closed = false
        @current_schema = previous_schema
        @cached_etag = compute_etag(previous_schema) if previous_schema
        @polling_thread = nil
        @mutex = Mutex.new
        @connection_attempts = 0

        # Validate polling interval
        validate_polling_interval!

        # RPC client for schema fetching with ETag support
        @rpc_client = RpcClient.new(@uri, @auth_secret)
      end

      # Start schema polling with initial synchronous fetch
      # The first schema fetch is done synchronously (blocking) to ensure
      # the schema is available immediately. Then async polling starts.
      #
      # @return [Boolean] true if started successfully, false if already running or closed
      def start # rubocop:disable Naming/PredicateMethod
        return false if @closed

        @mutex.synchronize do
          return false if @polling_thread&.alive?

          # Fetch initial schema synchronously before starting the polling thread
          ForestAdminAgent::Facades::Container.logger&.log('Info', "Getting schema from RPC agent on #{@uri}.")
          fetch_initial_schema_sync

          # Start async polling thread
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
        true
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

      # Compute ETag from schema using same algorithm as RPC slave
      # @param schema [Hash] The schema to hash
      # @return [String, nil] SHA1 hexdigest of schema JSON, or nil if schema is nil
      def compute_etag(schema)
        return nil if schema.nil?

        require 'digest'
        require 'json'
        Digest::SHA1.hexdigest(schema.to_json)
      end

      # Fetch initial schema synchronously (called from start() in main thread)
      # This is a blocking call that sets @current_schema and @cached_etag
      def fetch_initial_schema_sync
        result = @rpc_client.fetch_schema('/forest/rpc-schema')
        @current_schema = result.body
        @cached_etag = compute_etag(@current_schema)
        ForestAdminAgent::Facades::Container.logger&.log(
          'Debug',
          "[Schema Polling] Initial schema fetched successfully (ETag: #{@cached_etag})"
        )
      rescue Faraday::ConnectionFailed => e
        ForestAdminAgent::Facades::Container.logger&.log(
          'Error',
          "Connection failed to RPC agent at #{@uri}: #{e.message}\n#{e.backtrace.join("\n")}"
        )
      rescue Faraday::TimeoutError => e
        ForestAdminAgent::Facades::Container.logger&.log(
          'Error',
          "Request timeout to RPC agent at #{@uri}: #{e.message}"
        )
      rescue ForestAdminAgent::Http::Exceptions::AuthenticationOpenIdClient => e
        ForestAdminAgent::Facades::Container.logger&.log(
          'Error',
          "Authentication failed with RPC agent at #{@uri}: #{e.message}"
        )
      rescue StandardError => e
        ForestAdminAgent::Facades::Container.logger&.log(
          'Error',
          "Failed to get schema from RPC agent at #{@uri}: #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}"
        )
      end

      def polling_loop
        etag_status = @cached_etag ? "with ETag: #{@cached_etag}" : 'without initial ETag'
        ForestAdminAgent::Facades::Container.logger&.log(
          'Debug',
          "[Schema Polling] Starting polling loop (interval: #{@polling_interval}s, #{etag_status})"
        )

        first_check = true

        loop do
          break if @closed

          # Wait before checking (skip wait on first iteration to start polling immediately)
          unless first_check
            etag_info = @cached_etag || 'none'
            ForestAdminAgent::Facades::Container.logger&.log(
              'Debug',
              "[Schema Polling] Waiting #{@polling_interval}s before next check (current ETag: #{etag_info})"
            )
            sleep_with_interrupt(@polling_interval)
            break if @closed
          end
          first_check = false

          # Check for schema changes
          begin
            check_schema
          rescue StandardError => e
            handle_error(e)
          end
        end
      end

      def sleep_with_interrupt(duration)
        remaining = duration
        while remaining.positive? && !@closed
          sleep([remaining, 1].min)
          remaining -= 1
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

        ForestAdminAgent::Facades::Container.logger&.log(
          'Debug',
          '[Schema Polling] Invoking schema change callback'
        )
        begin
          @on_schema_change.call(schema)
          ForestAdminAgent::Facades::Container.logger&.log(
            'Debug',
            '[Schema Polling] Schema change callback completed successfully'
          )
        rescue StandardError => e
          error_msg = "[Schema Polling] Error in schema change callback: #{e.class} - #{e.message}"
          backtrace = "\n#{e.backtrace&.first(5)&.join("\n")}"
          ForestAdminAgent::Facades::Container.logger&.log('Error', error_msg + backtrace)
        end
      end

      def log_checking_schema
        etag_info = @cached_etag ? "with ETag: #{@cached_etag}" : 'without ETag (initial fetch)'
        msg = "[Schema Polling] Checking schema from #{@uri}/forest/rpc-schema " \
              "(attempt ##{@connection_attempts}, #{etag_info})"
        ForestAdminAgent::Facades::Container.logger&.log('Debug', msg)
      end

      def handle_schema_result(result)
        if result == RpcClient::NotModified
          handle_schema_unchanged
        else
          handle_schema_changed(result)
        end
      end

      def handle_schema_unchanged
        ForestAdminAgent::Facades::Container.logger&.log(
          'Debug',
          "[Schema Polling] Schema unchanged (HTTP 304 Not Modified), ETag still valid: #{@cached_etag}"
        )
        @connection_attempts = 0
      end

      def handle_schema_changed(result)
        new_schema = result.body
        new_etag = compute_etag(new_schema)

        if @cached_etag.nil?
          # Initial schema fetch
          @cached_etag = new_etag
          @current_schema = new_schema
          ForestAdminAgent::Facades::Container.logger&.log(
            'Debug',
            "[Schema Polling] Initial schema loaded successfully (ETag: #{new_etag})"
          )
        else
          # Schema update detected
          handle_schema_update(new_schema, new_etag)
        end
        @connection_attempts = 0
      end

      def handle_schema_update(schema, etag)
        old_etag = @cached_etag
        @cached_etag = etag
        @current_schema = schema
        msg = "[Schema Polling] Schema changed detected (old ETag: #{old_etag}, new ETag: #{etag}), " \
              'triggering reload callback'
        ForestAdminAgent::Facades::Container.logger&.log('Info', msg)
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
  end
end
