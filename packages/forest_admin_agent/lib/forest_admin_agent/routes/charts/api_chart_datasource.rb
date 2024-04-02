require 'jsonapi-serializers'
require 'active_support/inflector'

module ForestAdminAgent
  module Routes
    module Charts
      class ApiChartDatasource < AbstractAuthenticatedRoute
        def initialize(chart_name)
          @chart_name = chart_name
          @datasource = ForestAdminAgent::Facades::Container.datasource

          super()
        end

        def setup_routes
          # Mount both GET and POST, respectively for smart and api charts.
          slug = @chart_name.parameterize

          add_route(
            "forest_chart_get_#{slug}",
            'get',
            "/_charts/#{slug}",
            proc { handle_smart_chart }
          )

          add_route(
            "forest_chart_post_#{slug}",
            'post',
            "/_charts/#{slug}",
            proc { handle_api_chart }
          )

          self
        end

        def handle_api_chart
          {
            content: Serializer::ForestChartSerializer.serialize(
              @datasource.render_chart(
                @caller,
                @chart_name
              )
            )
          }
        end

        def handle_smart_chart
          {
            content: @datasource.render_chart(
              @caller,
              @chart_name
            )
          }
        end
      end
    end
  end
end
