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
      response = rpc_client.call_rpc('/forest/rpc-schema', method: :get, symbolize_keys: true)
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
      sse = Utils::SseClient.new("#{uri}/forest/sse", auth_secret) do
        ForestAdminAgent::Facades::Container.logger.log('Info', 'RPC server stopped, checking schema...')

        # Send If-None-Match header to check if schema has changed (304 optimization)
        result = rpc_client.call_rpc(
          '/forest/rpc-schema',
          method: :get,
          symbolize_keys: true,
          if_none_match: cached_etag
        )

        # If we get NotModified, schema hasn't changed
        if result == Utils::RpcClient::NotModified
          ForestAdminAgent::Facades::Container.logger.log('Debug', '[RPCDatasource] Schema has not changed (304)')
        else
          # Schema has changed, update the cached ETag and reload
          cached_etag = result.etag
          ForestAdminAgent::Builder::AgentFactory.instance.reload!
        end
      end
      sse.start

      datasource = ForestAdminDatasourceRpc::Datasource.new(options, schema, sse)

      # Setup cleanup hooks for proper SSE client shutdown
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
