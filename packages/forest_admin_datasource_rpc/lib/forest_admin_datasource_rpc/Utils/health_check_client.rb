require 'openssl'
require 'json'
require 'time'
require 'faraday'

module ForestAdminDatasourceRpc
  module Utils
    class HealthCheckClient
      attr_reader :closed

      DEFAULT_POLLING_INTERVAL = 30 # seconds
      DEFAULT_FAILURE_THRESHOLD = 3 # consecutive failures before triggering callback
      MAX_BACKOFF_DELAY = 30 # seconds
      INITIAL_BACKOFF_DELAY = 2 # seconds

      def initialize(uri, auth_secret, options = {}, &on_server_down)
        @uri = uri
        @auth_secret = auth_secret
        @polling_interval = options[:polling_interval] || DEFAULT_POLLING_INTERVAL
        @failure_threshold = options[:failure_threshold] || DEFAULT_FAILURE_THRESHOLD
        @on_server_down = on_server_down
        @closed = false
        @consecutive_failures = 0
        @polling_thread = nil
        @mutex = Mutex.new
        @server_down_triggered = false
        @connection_attempts = 0

        # HTTP client with reasonable timeouts
        @http_client = Faraday.new do |conn|
          conn.options.timeout = 5
          conn.options.open_timeout = 5
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
              "[Health Check] Unexpected error in polling loop: #{e.class} - #{e.message}"
            )
          end
        end

        ForestAdminAgent::Facades::Container.logger&.log('Debug', '[Health Check] Polling started')
      end

      def stop
        return if @closed

        @closed = true
        ForestAdminAgent::Facades::Container.logger&.log('Debug', '[Health Check] Stopping polling')

        @mutex.synchronize do
          if @polling_thread&.alive?
            @polling_thread.kill
            @polling_thread = nil
          end
        end

        ForestAdminAgent::Facades::Container.logger&.log('Debug', '[Health Check] Polling stopped')
      end

      private

      def polling_loop
        ForestAdminAgent::Facades::Container.logger&.log(
          'Debug',
          "[Health Check] Starting polling loop (interval: #{@polling_interval}s, threshold: #{@failure_threshold})"
        )

        loop do
          break if @closed

          begin
            if check_health
              handle_success
            else
              handle_failure
            end
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

      def check_health
        @connection_attempts += 1
        timestamp = Time.now.utc.iso8601(3)
        signature = generate_signature(timestamp)

        headers = {
          'X_TIMESTAMP' => timestamp,
          'X_SIGNATURE' => signature
        }

        ForestAdminAgent::Facades::Container.logger&.log(
          'Debug',
          "[Health Check] Checking health at #{@uri} (attempt ##{@connection_attempts})"
        )

        response = @http_client.get(@uri, nil, headers)

        if response.success?
          body = JSON.parse(response.body)
          if body['status'] == 'ok'
            ForestAdminAgent::Facades::Container.logger&.log(
              'Debug',
              "[Health Check] Health check successful (version: #{body['version']})"
            )
            return true
          else
            ForestAdminAgent::Facades::Container.logger&.log(
              'Warn',
              "[Health Check] Unexpected status: #{body['status']}"
            )
            return false
          end
        else
          ForestAdminAgent::Facades::Container.logger&.log(
            'Warn',
            "[Health Check] HTTP #{response.status}: #{response.body}"
          )
          return false
        end
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
        ForestAdminAgent::Facades::Container.logger&.log(
          'Debug',
          "[Health Check] Connection error: #{e.class}"
        )
        false
      rescue JSON::ParserError => e
        ForestAdminAgent::Facades::Container.logger&.log(
          'Warn',
          "[Health Check] Invalid JSON response: #{e.message}"
        )
        false
      end

      def handle_success
        # Reset failures and server down flag on successful health check
        if @consecutive_failures > 0
          ForestAdminAgent::Facades::Container.logger&.log(
            'Info',
            '[Health Check] Server is back online'
          )
        end

        @consecutive_failures = 0
        @server_down_triggered = false
        @connection_attempts = 0
      end

      def handle_failure
        @consecutive_failures += 1

        ForestAdminAgent::Facades::Container.logger&.log(
          'Warn',
          "[Health Check] Health check failed (#{@consecutive_failures}/#{@failure_threshold})"
        )

        # Trigger callback only once when threshold is reached
        if @consecutive_failures >= @failure_threshold && !@server_down_triggered
          @server_down_triggered = true
          trigger_server_down_callback
        end
      end

      def handle_error(error)
        ForestAdminAgent::Facades::Container.logger&.log(
          'Error',
          "[Health Check] Error during health check: #{error.class} - #{error.message}"
        )
        handle_failure
      end

      def trigger_server_down_callback
        ForestAdminAgent::Facades::Container.logger&.log(
          'Warn',
          "[Health Check] Server appears to be down after #{@consecutive_failures} consecutive failures"
        )

        return unless @on_server_down

        begin
          @on_server_down.call
        rescue StandardError => e
          ForestAdminAgent::Facades::Container.logger&.log(
            'Error',
            "[Health Check] Error in server down callback: #{e.class} - #{e.message}"
          )
        end
      end

      def generate_signature(timestamp)
        OpenSSL::HMAC.hexdigest('SHA256', @auth_secret, timestamp)
      end
    end
  end
end
