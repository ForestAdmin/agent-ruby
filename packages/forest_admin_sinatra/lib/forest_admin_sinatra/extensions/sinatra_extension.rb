require 'sinatra/base'

module ForestAdminSinatra
  module Extensions
    module SinatraExtension
      def self.registered(app)
        ForestAdminAgent::Builder::AgentFactory.instance.setup(ForestAdminSinatra.config)

        route_classes = ForestAdminSinatra::Routes.constants.reject { |route| route.name == 'BaseRoute' }
        route_classes.each do |route|
          route_class = ForestAdminSinatra::Routes.const_get(route)

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

Sinatra::Base.register ForestAdminSinatra::Extensions::SinatraExtension
