require 'openssl'
require 'json'
require 'time'
require 'digest'

module ForestAdminDatasourceRpc
  module Utils
    class SchemaPollingClient
      attr_reader :closed, :current_schema, :client_id

      DEFAULT_POLLING_INTERVAL = 600
      MIN_POLLING_INTERVAL = 1
      MAX_POLLING_INTERVAL = 3600

      def initialize(uri, auth_secret, polling_interval: DEFAULT_POLLING_INTERVAL, introspection_schema: nil,
                     introspection_etag: nil, &on_schema_change)
        @uri = uri
        @auth_secret = auth_secret
        @polling_interval = polling_interval
        @on_schema_change = on_schema_change
        @closed = false
        @introspection_schema = introspection_schema
        @introspection_etag = introspection_etag
        @current_schema = nil
        @cached_etag = nil
        @connection_attempts = 0
        @initial_sync_completed = false
        @client_id = uri

        validate_polling_interval!

        @rpc_client = RpcClient.new(@uri, @auth_secret)
      end

      def start?
        return false if @closed

        ForestAdminAgent::Facades::Container.logger&.log('Info', "Getting schema from RPC agent on #{@uri}.")
        fetch_initial_schema_sync

        # Register with the shared pool
        SchemaPollingPool.instance.register?(@client_id, self)

        ForestAdminAgent::Facades::Container.logger&.log(
          'Info',
          "[Schema Polling] Registered with pool (interval: #{@polling_interval}s, client: #{@client_id})"
        )
        true
      end

      def stop
        return if @closed

        @closed = true
        ForestAdminAgent::Facades::Container.logger&.log('Debug', '[Schema Polling] Stopping polling')

        SchemaPollingPool.instance.unregister?(@client_id)

        ForestAdminAgent::Facades::Container.logger&.log('Debug', '[Schema Polling] Polling stopped')
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
      rescue ForestAdminDatasourceToolkit::Exceptions::ForestException => e
        log_rpc_error(e)
      rescue StandardError => e
        log_unexpected_error(e)
      end

      private

      def compute_etag(schema)
        return nil if schema.nil?

        schema[:etag] || schema['etag'] || Digest::SHA1.hexdigest(JSON.generate(schema))
      end

      def fetch_initial_schema_sync
        # If we have an introspection schema, send its ETag to avoid re-downloading unchanged schema
        introspection_etag = @introspection_etag || (@introspection_schema && compute_etag(@introspection_schema))
        result = @rpc_client.fetch_schema('/forest/rpc-schema', if_none_match: introspection_etag)

        if result == RpcClient::NotModified
          # Schema unchanged from introspection - use introspection
          @current_schema = @introspection_schema
          @cached_etag = introspection_etag
          @initial_sync_completed = true
          ForestAdminAgent::Facades::Container.logger&.log(
            'Info',
            "[Schema Polling] RPC schema unchanged (HTTP 304), using introspection (ETag: #{@cached_etag})"
          )
        else
          # New schema from RPC
          @current_schema = result.body
          @cached_etag = result.etag || compute_etag(@current_schema)
          @initial_sync_completed = true
          ForestAdminAgent::Facades::Container.logger&.log(
            'Debug',
            "[Schema Polling] Initial schema fetched successfully (ETag: #{@cached_etag})"
          )
        end

        @introspection_schema = nil
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError,
             ForestAdminAgent::Http::Exceptions::AuthenticationOpenIdClient,
             ForestAdminDatasourceToolkit::Exceptions::ForestException, StandardError => e
        handle_initial_fetch_error(e)
      end

      def handle_initial_fetch_error(error)
        if @introspection_schema
          # Fallback to introspection schema - don't crash
          @current_schema = @introspection_schema
          @cached_etag = @introspection_etag || compute_etag(@current_schema)
          @introspection_schema = nil
          @introspection_etag = nil
          @initial_sync_completed = true
          ForestAdminAgent::Facades::Container.logger&.log(
            'Warn',
            "RPC agent at #{@uri} is unreachable (#{error.class}: #{error.message}), " \
            "using provided introspection schema (ETag: #{@cached_etag})"
          )
        else
          # No introspection - re-raise to crash
          ForestAdminAgent::Facades::Container.logger&.log(
            'Error',
            "Failed to get schema from RPC agent at #{@uri}: #{error.class} - #{error.message}"
          )
          raise error
        end
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
        new_etag = result.etag || compute_etag(new_schema)

        if @initial_sync_completed
          handle_schema_update(new_schema, new_etag)
        else
          @cached_etag = new_etag
          @current_schema = new_schema
          @initial_sync_completed = true
          ForestAdminAgent::Facades::Container.logger&.log(
            'Info',
            "[Schema Polling] Initial sync completed successfully (ETag: #{new_etag})"
          )
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

      def log_rpc_error(error)
        ForestAdminAgent::Facades::Container.logger&.log(
          'Warn',
          "[Schema Polling] RPC error: #{error.message}"
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
