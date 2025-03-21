module ForestAdminSinatra
  module Routes
    class BaseRoute
      def initialize(url, method, name)
        @url = url
        @method = method
        @name = name
      end

      def registered(app)
        if defined?(Sinatra) && (app == Sinatra::Base || app.ancestors.include?(Sinatra::Base))
          app.send(@method.to_sym, @url) do
            handle_request(params)
          end
        else
          raise NotImplementedError,
                "Unsupported application type: #{app.class}. #{self} works with Sinatra::Base."
        end
      end
    end
  end
end
