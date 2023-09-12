module ForestAdminAgent
  module Routes
    class AbstractRoute
      attr_reader :request

      def initialize
        @request = ActionDispatch::Request.new({})
        @routes = {}
        setup_routes
      end

      def routes
        @routes ||= {}
      end

      def add_route(name, method, uri, closure)
        @routes[name] = { method: method, uri: uri, closure: closure }
      end

      def setup_routes
        raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
      end
    end
  end
end
