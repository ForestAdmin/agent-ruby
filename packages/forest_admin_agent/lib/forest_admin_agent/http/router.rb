module ForestAdminAgent
  module Http
    class Router
      include ForestAdminAgent::Routes

      def self.routes
        [
          # actions_routes,
          # api_charts_routes,
          System::HealthCheck.new.routes,
          Security::Authentication.new.routes,
          Resources::List.new.routes,
          Resources::Count.new.routes
        ].inject(&:merge)
      end

      def self.actions_routes
        routes = []
        # TODO
        # AgentFactory.get('datasource').collections.each do |collection|
        #   collection.get_actions.each do |action_name, action|
        #     routes << Actions.new(collection, action_name).routes
        #   end
        # end
        routes.flatten
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
