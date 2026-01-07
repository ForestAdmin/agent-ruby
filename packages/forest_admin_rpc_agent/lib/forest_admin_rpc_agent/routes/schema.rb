module ForestAdminRpcAgent
  module Routes
    class Schema < BaseRoute
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminAgent::Utils
      include ForestAdminAgent::Routes::QueryHandler

      HTTP_OK = 200
      HTTP_NOT_MODIFIED = 304

      def initialize
        super('rpc-schema', 'get', 'rpc_schema')
      end

      def handle_request(args)
        agent = ForestAdminRpcAgent::Agent.instance
        client_etag = extract_if_none_match(args)

        # If client has cached schema and ETag matches, return 304 Not Modified
        if client_etag && agent.schema_hash_matches?(client_etag)
          ForestAdminRpcAgent::Facades::Container.logger.log(
            'Debug',
            'ETag matches, returning 304 Not Modified'
          )
          return { status: HTTP_NOT_MODIFIED, content: nil,
                   headers: { 'ETag' => quote_etag(agent.cached_schema_hash) } }
        end

        # Get schema from cache (or build from datasource if not cached)
        schema = agent.cached_schema
        etag = agent.cached_schema_hash

        # Return schema with ETag header
        {
          status: HTTP_OK,
          content: schema,
          headers: { 'ETag' => quote_etag(etag) }
        }
      end

      private

      def extract_if_none_match(args)
        request = args[:request] if args.is_a?(Hash)
        return nil unless request

        # Get If-None-Match header (works for both Rails and Sinatra)
        etag = if request.respond_to?(:get_header)
                 request.get_header('HTTP_IF_NONE_MATCH')
               elsif request.respond_to?(:env)
                 request.env['HTTP_IF_NONE_MATCH']
               end

        # Strip quotes from ETag value if present
        unquote_etag(etag)
      end

      def quote_etag(etag)
        return nil unless etag

        %("#{etag}")
      end

      def unquote_etag(etag)
        return nil unless etag

        etag.gsub(/\A"?|"?\z/, '')
      end
    end
  end
end
