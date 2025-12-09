require_relative 'forest_admin_datasource_rpc/version'
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/models")
loader.setup

module ForestAdminDatasourceRpc
  class Error < StandardError; end

  def self.build(options)
    uri = options[:uri]
    auth_secret = options[:auth_secret] || ForestAdminAgent::Facades::Container.cache(:auth_secret)
    ForestAdminAgent::Facades::Container.logger.log('Info', "Getting schema from RPC agent on #{uri}.")

    schema = nil
    cached_etag = nil

    begin
      rpc_client = Utils::RpcClient.new(uri, auth_secret)
      response = rpc_client.fetch_schema('/forest/rpc-schema')
      schema = response.body
      # Use the ETag header for conditional requests
      cached_etag = response.etag
    rescue Faraday::ConnectionFailed => e
      ForestAdminAgent::Facades::Container.logger.log(
        'Error',
        "Connection failed to RPC agent at #{uri}: #{e.message}\n#{e.backtrace.join("\n")}"
      )
    rescue Faraday::TimeoutError => e
      ForestAdminAgent::Facades::Container.logger.log(
        'Error',
        "Request timeout to RPC agent at #{uri}: #{e.message}"
      )
    rescue ForestAdminAgent::Http::Exceptions::AuthenticationOpenIdClient => e
      ForestAdminAgent::Facades::Container.logger.log(
        'Error',
        "Authentication failed with RPC agent at #{uri}: #{e.message}"
      )
    rescue StandardError => e
      ForestAdminAgent::Facades::Container.logger.log(
        'Error',
        "Failed to get schema from RPC agent at #{uri}: #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}"
      )
    end

    if schema.nil?
      # return empty datasource for not breaking stack
      ForestAdminDatasourceToolkit::Datasource.new
    else
      # Create health check client with configurable polling interval and failure threshold
      health_check_options = {
        polling_interval: options[:health_check_interval] || 30,
        failure_threshold: options[:health_check_failure_threshold] || 3
      }

      health_check = Utils::HealthCheckClient.new("#{uri}/forest/health", auth_secret, health_check_options) do
        ForestAdminAgent::Facades::Container.logger.log('Info', 'RPC server appears down, checking schema...')
        begin
          new_schema = rpc_client.call_rpc('/forest/rpc-schema', method: :get, symbolize_keys: true)

          if last_hash_schema == Digest::SHA1.hexdigest(new_schema.to_h.to_s)
            ForestAdminAgent::Facades::Container.logger.log('Debug', '[RPCDatasource] Schema has not changed')
          else
            ForestAdminAgent::Builder::AgentFactory.instance.reload!
          end
        rescue StandardError => e
          ForestAdminAgent::Facades::Container.logger.log(
            'Warn',
            "[RPCDatasource] Failed to check schema after server down: #{e.class} - #{e.message}"
          )
        end
      end
      health_check.start

      datasource = ForestAdminDatasourceRpc::Datasource.new(options, schema, health_check)

      # Setup cleanup hooks for proper health check client shutdown
      setup_cleanup_hooks(datasource)

      datasource
    end
  end

  def self.setup_cleanup_hooks(datasource)
    # Register cleanup handler for graceful shutdown
    at_exit do
      datasource.cleanup
    rescue StandardError => e
      # Silently ignore errors during exit cleanup to prevent test pollution
      warn "[RPCDatasource] Error during at_exit cleanup: #{e.message}" if $VERBOSE
    end

    # Handle SIGINT (Ctrl+C)
    Signal.trap('INT') do
      begin
        ForestAdminAgent::Facades::Container.logger&.log('Info', '[RPCDatasource] Received SIGINT, cleaning up...')
      rescue StandardError
        # Logger might not be available
      end
      datasource.cleanup
      exit(0)
    end

    # Handle SIGTERM (default kill signal)
    Signal.trap('TERM') do
      begin
        ForestAdminAgent::Facades::Container.logger&.log('Info', '[RPCDatasource] Received SIGTERM, cleaning up...')
      rescue StandardError
        # Logger might not be available
      end
      datasource.cleanup
      exit(0)
    end
  end
end
