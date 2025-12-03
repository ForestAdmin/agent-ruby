module ForestAdminAgent
  module Routes
    class AbstractRoute
      def initialize
        @routes = {}
        setup_routes
      end

      def build(args)
        context = RequestContext.new
        context.datasource = ForestAdminAgent::Facades::Container.datasource

        if args[:params]['collection_name']
          begin
            context.collection = context.datasource.get_collection(args[:params]['collection_name'])
          rescue ForestAdminDatasourceToolkit::Exceptions::ForestException => e
            raise Http::Exceptions::NotFoundError, e.message if e.message.include?('not found')

            raise
          end
        end

        context
      end

      def routes
        @routes ||= {}
      end

      def add_route(name, method, uri, closure, format = 'json')
        @routes[name] = { method: method, uri: uri, closure: closure, format: format }
      end

      def setup_routes
        raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
      end
    end
  end
end
