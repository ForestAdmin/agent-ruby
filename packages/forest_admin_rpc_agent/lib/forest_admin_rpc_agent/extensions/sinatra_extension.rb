require 'sinatra/base'

module ForestAdminRpcAgent
  module Extensions
    module SinatraExtension
      def self.registered(app)
        app.before do
          agent = ForestAdminRpcAgent::Agent.instance
          agent.setup(ForestAdminRpcAgent.config)
          ForestAdminRpcAgent::Extensions::ConfigLoader.load_configuration
        end

        app.use ForestAdminRpcAgent::Middleware::Authentication

        route_classes = ForestAdminRpcAgent::Routes.constants.reject { |route| route.name == 'BaseRoute' }
        route_classes.each do |route|
          route_class = ForestAdminRpcAgent::Routes.const_get(route)

          if route_class.respond_to?(:registered)
            puts "Registering #{route_class}"
            route_class.registered(app)
          else
            ForestAdminAgent::Facades::Container.logger.log('warn',
                                                            "Skipping #{route_class} (does not respond to :registered)")
          end
        end
      end
    end
  end
end

Sinatra::Base.register ForestAdminRpcAgent::Extensions::SinatraExtension
