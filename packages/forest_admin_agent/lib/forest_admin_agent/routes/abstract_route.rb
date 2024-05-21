module ForestAdminAgent
  module Routes
    class AbstractRoute
      def initialize
        @routes = {}
        setup_routes
      end

      def build(args)
        @datasource = ForestAdminAgent::Facades::Container.datasource
        @collection = @datasource.get_collection(args[:params]['collection_name'])
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
