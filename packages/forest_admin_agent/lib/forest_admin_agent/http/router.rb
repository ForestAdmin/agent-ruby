module ForestAdminAgent
  module Http
    class Router
      include ForestAdminAgent::Routes

      def self.routes
        [
          actions_routes,
          # api_charts_routes,
          System::HealthCheck.new.routes,
          Security::Authentication.new.routes,
          Charts::Charts.new.routes,
          Resources::Count.new.routes,
          Resources::Delete.new.routes,
          Resources::List.new.routes,
          Resources::Show.new.routes,
          Resources::Store.new.routes,
          Resources::Update.new.routes,
          Resources::Related::ListRelated.new.routes,
          Resources::Related::CountRelated.new.routes,
          Resources::Related::AssociateRelated.new.routes,
          Resources::Related::DissociateRelated.new.routes,
          Resources::Related::UpdateRelated.new.routes
        ].inject(&:merge)
      end

      def self.actions_routes
        routes = {}
        Facades::Container.datasource.collections.each_value do |collection|
          collection.schema[:actions].each_key do |action_name|
            routes.merge!(Action::Action.new(collection, action_name).routes)
          end
        end

        routes
      end

      def self.api_charts_routes
        routes = []
        # TODO
        # AgentFactory.get('datasource').charts.each do |chart|
        #   routes << ApiChartDatasource.new(chart).routes
        # end
        # AgentFactory.get('datasource').collections.each do |collection|
        #   collection.charts.each do |chart|
        #     routes << ApiChartCollection.new(collection, chart).routes
        #   end
        # end
        routes.flatten
      end
    end
  end
end
