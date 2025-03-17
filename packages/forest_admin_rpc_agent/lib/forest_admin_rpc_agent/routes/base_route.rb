# module ForestAdminRpcAgent
#   module Routes
#     if defined?(Sinatra)
#       require 'sinatra/base'
#     end
#
#     class BaseRoute
#       def self.registered(app)
#         raise NotImplementedError, "Each route class must implement `.registered`"
#       end
#     end
#   end
# end

module ForestAdminRpcAgent
  module Routes
    class BaseRoute
      def self.registered(app)
        if defined?(Sinatra) && app.is_a?(Sinatra::Base)
          register_sinatra(app)
        elsif defined?(Rails) && app.is_a?(ActionDispatch::Routing::Mapper)
          register_rails(app)
        else
          raise NotImplementedError,
                "Unsupported application type: #{app.class}. #{self} works with Sinatra::Base or ActionDispatch::Routing::Mapper."
        end
      end

      def self.register_sinatra(app)
        raise NotImplementedError, "#{self} must implement `register_sinatra`"
      end

      def self.register_rails(router)
        raise NotImplementedError, "#{self} must implement `register_rails`"
      end
    end
  end
end
