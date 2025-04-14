module ForestAdminSinatra
  module Routes
    class BaseRoute
      def initialize(uri:, method:, name:, closure:, format:)
        @uri = uri
        @method = method
        @name = name
        @closure = closure
        @format = format
      end

      def registered(app)
        if defined?(Sinatra) && (app == Sinatra::Base || app.ancestors.include?(Sinatra::Base))
          app.send(@method.downcase.to_sym, @uri) do
            [200, { 'Content-Type' => 'application/json' }, [@closure.send(Sinatra::Request.new(env).params)]]
          end
        else
          raise NotImplementedError,
                "Unsupported application type: #{app.class}. #{self} works with Sinatra::Base."
        end
      end
    end
  end
end
