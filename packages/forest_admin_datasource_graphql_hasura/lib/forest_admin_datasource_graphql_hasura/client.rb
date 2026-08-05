require 'json'
require 'openssl'
require 'net/http'
require 'uri'

module ForestAdminDatasourceGraphqlHasura
  # GraphQL-over-HTTP client for Hasura (queries, mutations and the metadata
  # API), on Net::HTTP so the gem needs no HTTP dependency.
  class Client
    def initialize(configuration)
      @configuration = configuration
    end

    # Wrapped in TransportError (503) so they reach the user as an actionable
    # message without masquerading as a client mistake: errors Hasura itself
    # returns are the only ones raised as GraphqlError (400).
    TRANSPORT_ERRORS = [
      Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Net::HTTPBadResponse, IOError, SocketError,
      SystemCallError, OpenSSL::SSL::SSLError, JSON::ParserError
    ].freeze

    def execute(query, variables = {})
      body = JSON.generate({ query: query, variables: variables })
      response = post(@configuration.uri, body)

      raise TransportError, "GraphQL endpoint returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(response.body)
      raise TransportError, 'GraphQL endpoint returned an unexpected body' unless payload.is_a?(Hash)

      if payload['errors']&.any?
        messages = payload['errors'].map { |e| e['message'] }.join('; ')
        raise GraphqlError, messages
      end

      # A 200 with neither data nor errors is malformed, and letting a nil out
      # would crash the caller with an opaque NoMethodError.
      data = payload['data']
      raise TransportError, 'GraphQL endpoint returned no data' if data.nil?

      data
    rescue *TRANSPORT_ERRORS => e
      raise TransportError, "Could not reach the GraphQL endpoint (#{e.class}): #{e.message}"
    end

    # Returns nil when the endpoint is unreachable or forbidden, which is common
    # in production: introspection then falls back to the configuration and to
    # naming conventions.
    def fetch_metadata
      if @configuration.metadata_uri.nil?
        ForestAdminDatasourceGraphqlHasura.logger.info(
          '[forest_admin_datasource_graphql_hasura] No metadata endpoint could be derived from uri ' \
          "(no '/v1/graphql' segment); set the 'metadata_uri' option to enable relationship detection."
        )
        return nil
      end

      body = JSON.generate({ type: 'export_metadata', version: 2, args: {} })
      response = post(@configuration.metadata_uri, body)

      return nil unless response.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(response.body)
      metadata = payload['metadata'] || payload

      metadata['sources'] ? metadata : nil
    rescue StandardError => e
      ForestAdminDatasourceGraphqlHasura.logger.info(
        "[forest_admin_datasource_graphql_hasura] Hasura metadata API not available (#{e.class}); " \
        'falling back to configuration and naming conventions.'
      )
      nil
    end

    private

    def post(url, body)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.read_timeout = @configuration.timeout
      http.open_timeout = @configuration.timeout
      http.write_timeout = @configuration.timeout

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      @configuration.headers.each { |key, value| request[key] = value }
      request.body = body

      http.request(request)
    end
  end
end
