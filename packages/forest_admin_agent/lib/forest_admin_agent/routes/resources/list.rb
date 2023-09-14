module ForestAdminAgent
  module Routes
    module Resources
      class List < AbstractRoute
        include ForestAdminAgent::Builder
        def setup_routes
          add_route('forest_list', 'get', '/:collection_name', ->(args) { handle_request(args) })

          self
        end

        def handle_request(args = {})
          { name: args['collection_name'], content: args['collection_name'] }
        end
      end
    end
  end
end
