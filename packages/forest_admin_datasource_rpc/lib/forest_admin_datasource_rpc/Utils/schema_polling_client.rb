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

        # Add If-None-Match header if we have a cached ETag (enables 304 optimization)
        headers['If-None-Match'] = quote_etag(@last_etag) if @last_etag

        ForestAdminAgent::Facades::Container.logger&.log(
          'Debug',
          "[Schema Polling] Fetching schema from #{@uri}/forest/rpc-schema (attempt ##{@connection_attempts})" +
            (@last_etag ? " [ETag: #{@last_etag}]" : '')
        )

        response = @http_client.get("#{@uri}/forest/rpc-schema", nil, headers)

        if response.status == 304
          # 304 Not Modified - schema hasn't changed (ETag optimization)
          ForestAdminAgent::Facades::Container.logger&.log(
            'Debug',
            '[Schema Polling] Schema unchanged (304 Not Modified)'
          )
          @connection_attempts = 0
        elsif response.success?
          # 200 OK - parse schema and update ETag
          schema = JSON.parse(response.body, symbolize_names: true)
          new_hash = Digest::SHA1.hexdigest(schema.to_h.to_s)
          new_etag = unquote_etag(response.headers['etag'] || response.headers['ETag'])

          # Update stored ETag if present
          @last_etag = new_etag if new_etag

          if @last_schema_hash.nil?
            # First poll - just store the hash
            @last_schema_hash = new_hash
            ForestAdminAgent::Facades::Container.logger&.log(
              'Debug',
              "[Schema Polling] Initial schema hash stored (ETag: #{@last_etag})"
            )
            @connection_attempts = 0
          elsif @last_schema_hash != new_hash
            # Schema changed - trigger callback
            ForestAdminAgent::Facades::Container.logger&.log(
              'Info',
              "[Schema Polling] Schema changed detected (ETag: #{@last_etag}), triggering reload callback"
            )
            @last_schema_hash = new_hash
            @connection_attempts = 0
            trigger_schema_change_callback(schema)
          else
            # Schema unchanged (same hash but 200 response, shouldn't happen with ETag)
            ForestAdminAgent::Facades::Container.logger&.log(
              'Debug',
              '[Schema Polling] Schema unchanged (same hash)'
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
  end
end
