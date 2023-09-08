# TODO: move to a new toolkit package
module ForestadminRails
  module Registry
    class AbstractRoute
      self.abstract_class = true
      attr_reader :request

      def routes
        @routes ||= []
      end

      # def initialize
      # end

      def add_route(name, methods, uri, closure)
        routes[name] = { methods: methods, uri: uri, closure: closure }
      end

      def self.make; end

      def self.setup_routes
        raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
      end
    end
  end
end
