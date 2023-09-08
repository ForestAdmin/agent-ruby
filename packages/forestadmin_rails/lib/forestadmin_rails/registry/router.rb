# TODO: move to a new agent package
module ForestadminRails
  module Registry
    class Router
      def self.routes
        [
          actions_routes,
          api_charts_routes
          # HealthCheck.make.routes,
        ]
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
