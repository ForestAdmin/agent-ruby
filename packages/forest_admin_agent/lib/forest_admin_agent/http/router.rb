module ForestAdminAgent
  module Http
    class Router
      include ForestAdminAgent::Routes

      def self.routes
        [
          actions_routes,
          api_charts_routes,
          System::HealthCheck.new.routes,
          Security::Authentication.new.routes,
          Security::ScopeInvalidation.new.routes,
          Charts::Charts.new.routes,
          Resources::Count.new.routes,
          Resources::Delete.new.routes,
          Resources::Csv.new.routes,
          Resources::List.new.routes,
          Resources::Show.new.routes,
          Resources::Store.new.routes,
          Resources::Update.new.routes,
          Resources::Related::CsvRelated.new.routes,
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
            routes.merge!(Action::Actions.new(collection, action_name).routes)
          end
        end

        routes
      end

      def self.api_charts_routes
        routes = {}
        Facades::Container.datasource.collections.each_value do |collection|
          collection.schema[:charts].each do |chart_name|
            routes.merge!(Charts::ApiChartCollection.new(collection, chart_name).routes)
          end
        end

        Facades::Container.datasource.schema[:charts].each do |chart_name|
          routes.merge!(Charts::ApiChartDatasource.new(chart_name).routes)
        end

        routes
      end
    end
  end
end
