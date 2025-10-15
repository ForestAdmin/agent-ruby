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
            proc { |args| handle_smart_chart(args) }
          )

          add_route(
            "forest_chart_post_#{slug}",
            'post',
            "/_charts/#{slug}",
            proc { |args| handle_api_chart(args) }
          )

          self
        end

        def handle_api_chart(args = {})
          @caller = Utils::QueryStringParser.parse_caller(args)

          {
            content: Serializer::ForestChartSerializer.serialize(
              @datasource.render_chart(
                @caller,
                @chart_name
              )
            )
          }
        end

        def handle_smart_chart(args = {})
          @caller = Utils::QueryStringParser.parse_caller(args)

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
