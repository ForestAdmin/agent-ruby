require 'jsonapi-serializers'
require 'active_support/inflector'

module ForestAdminAgent
  module Routes
    module Charts
      class ApiChartCollection < AbstractAuthenticatedRoute
        include ForestAdminAgent::Utils

        def initialize(collection, chart_name)
          @chart_name = chart_name
          @collection = collection

          super()
        end

        def setup_routes
          # Mount both GET and POST, respectively for smart and api charts.
          collection_name = @collection.name
          slug = @chart_name.parameterize

          add_route(
            "forest_chart_#{collection_name}_get_#{slug}",
            'get',
            "/_charts/:collection_name/#{slug}",
            proc { |args| handle_smart_chart(args) }
          )

          add_route(
            "forest_chart_#{collection_name}_post_#{slug}",
            'post',
            "/_charts/:collection_name/#{slug}",
            proc { |args| handle_api_chart(args) }
          )

          unless Facades::Container.cache(:is_production)
            # Facades::Container.logger.log(
            #   'Info',
            #   "Chart #{@chart_name} was mounted at /forest/_charts/#{collection_name}/#{slug}"
            # )
          end

          self
        end

        def handle_api_chart(args)
          build(args)
          {
            content: Serializer::ForestChartSerializer.serialize(
              @collection.render_chart(
                @caller,
                @chart_name,
                Id.unpack_id(@collection, args[:params]['record_id'])
              )
            )
          }
        end

        def handle_smart_chart(args)
          build(args)
          {
            content: @collection.render_chart(
              @caller,
              @chart_name,
              Id.unpack_id(@collection, args[:params]['record_id'])
            )
          }
        end
      end
    end
  end
end
