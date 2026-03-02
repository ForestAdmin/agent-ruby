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
        etag = agent.cached_schema_hash

        if client_etag && agent.schema_hash_matches?(client_etag)
          ForestAdminRpcAgent::Facades::Container.logger.log(
            'Debug',
            'ETag matches, returning 304 Not Modified'
          )
          return { status: HTTP_NOT_MODIFIED, content: nil,
                   headers: { 'ETag' => etag } }
        end

        schema = agent.cached_schema

        {
          status: HTTP_OK,
          content: schema,
          headers: { 'ETag' => etag }
        }
      end

      private

      def extract_if_none_match(args)
        request = args[:request] if args.is_a?(Hash)
        return nil unless request

        # Get If-None-Match header (works for both Rails and Sinatra)
        if request.respond_to?(:get_header)
          request.get_header('HTTP_IF_NONE_MATCH')
        elsif request.respond_to?(:env)
          request.env['HTTP_IF_NONE_MATCH']
        end
      end
    end
  end
end
