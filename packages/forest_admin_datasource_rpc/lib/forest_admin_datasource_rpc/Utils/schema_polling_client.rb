require 'openssl'
require 'json'
require 'time'
require 'faraday'
require 'digest'

module ForestAdminDatasourceRpc
  module Utils
    # Handles HTTP polling for schema changes with ETag support
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
        @last_schema_hash = nil
        @last_etag = options[:initial_etag] # Store initial ETag from first schema fetch
        @polling_thread = nil
        @mutex = Mutex.new
        @connection_attempts = 0

        # Validate polling interval
        validate_polling_interval!

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
        headers = build_request_headers
        log_fetch_attempt

        response = @http_client.get("#{@uri}/forest/rpc-schema", nil, headers)

        handle_response(response)
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
        log_connection_error(e)
      rescue JSON::ParserError => e
        log_json_error(e)
      end

      def build_request_headers
        timestamp = Time.now.utc.iso8601(3)
        headers = {
          'X_TIMESTAMP' => timestamp,
          'X_SIGNATURE' => generate_signature(timestamp)
        }
        headers['If-None-Match'] = quote_etag(@last_etag) if @last_etag
        headers
      end

      def log_fetch_attempt
        message = "[Schema Polling] Fetching schema from #{@uri}/forest/rpc-schema " \
                  "(attempt ##{@connection_attempts})"
        message += " [ETag: #{@last_etag}]" if @last_etag
        ForestAdminAgent::Facades::Container.logger&.log('Debug', message)
      end

      def handle_response(response)
        case response.status
        when 304
          handle_not_modified_response
        when 200..299
          handle_success_response(response)
        else
          handle_error_response(response)
        end
      end

      def handle_not_modified_response
        ForestAdminAgent::Facades::Container.logger&.log(
          'Debug',
          '[Schema Polling] Schema unchanged (304 Not Modified)'
        )
        @connection_attempts = 0
      end

      def handle_success_response(response)
        schema = JSON.parse(response.body, symbolize_names: true)
        new_hash = Digest::SHA1.hexdigest(schema.to_h.to_s)
        new_etag = unquote_etag(response.headers['etag'] || response.headers['ETag'])

        @last_etag = new_etag if new_etag

        if @last_schema_hash.nil?
          handle_first_poll(new_hash)
        elsif @last_schema_hash != new_hash
          handle_schema_change(new_hash, schema)
        else
          handle_unchanged_schema
        end
      end

      def handle_first_poll(new_hash)
        @last_schema_hash = new_hash
        @connection_attempts = 0
        ForestAdminAgent::Facades::Container.logger&.log(
          'Debug',
          "[Schema Polling] Initial schema hash stored (ETag: #{@last_etag})"
        )
      end

      def handle_schema_change(new_hash, schema)
        @last_schema_hash = new_hash
        @connection_attempts = 0
        ForestAdminAgent::Facades::Container.logger&.log(
          'Info',
          "[Schema Polling] Schema changed detected (ETag: #{@last_etag}), triggering reload callback"
        )
        trigger_schema_change_callback(schema)
      end

      def handle_unchanged_schema
        @connection_attempts = 0
        ForestAdminAgent::Facades::Container.logger&.log(
          'Debug',
          '[Schema Polling] Schema unchanged (same hash)'
        )
      end

      def handle_error_response(response)
        ForestAdminAgent::Facades::Container.logger&.log(
          'Warn',
          "[Schema Polling] HTTP #{response.status}: #{response.body}"
        )
      end

      def log_connection_error(error)
        ForestAdminAgent::Facades::Container.logger&.log(
          'Warn',
          "[Schema Polling] Connection error: #{error.class} - #{error.message}"
        )
      end

      def log_json_error(error)
        ForestAdminAgent::Facades::Container.logger&.log(
          'Error',
          "[Schema Polling] Invalid JSON response: #{error.message}"
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

      def validate_polling_interval!
        if @polling_interval < MIN_POLLING_INTERVAL
          raise ArgumentError,
                "Schema polling interval too short: #{@polling_interval}s (minimum: #{MIN_POLLING_INTERVAL}s)"
        elsif @polling_interval > MAX_POLLING_INTERVAL
          raise ArgumentError,
                "Schema polling interval too long: #{@polling_interval}s (maximum: #{MAX_POLLING_INTERVAL}s)"
        end
      end

      def quote_etag(etag)
        return nil unless etag

        # Add quotes if not already present
        etag.start_with?('"') ? etag : %("#{etag}")
      end

      def unquote_etag(etag)
        return nil unless etag

        # Remove quotes if present
        etag.gsub(/\A"?|"?\z/, '')
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
