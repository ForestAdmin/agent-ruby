require 'jsonapi-serializers'
require 'ostruct'

module ForestAdminAgent
  module Routes
    module Resources
      class Delete < AbstractAuthenticatedRoute
        include ForestAdminAgent::Builder
        include ForestAdminDatasourceToolkit::Components::Query

        def setup_routes
          add_route('forest_delete_bulk', 'delete', '/:collection_name', ->(args) { handle_request_bulk(args) })
          add_route('forest_delete', 'delete', '/:collection_name/:id', ->(args) { handle_request(args) })

          self
        end

        def handle_request(args = {})
          build(args)
          id = Utils::Id.unpack_id(@collection, args[:params]['id'], with_key: true)
          delete_records(args, { ids: [id], are_excluded: false })

          { content: nil, status: 204 }
        end

        def handle_request_bulk(args = {})
          build(args)
          selection_ids = Utils::Id.parse_selection_ids(@collection, args[:params], with_key: true)
          delete_records(args, selection_ids)

          { content: nil, status: 204 }
        end

        def delete_records(args, selection_ids)
          condition_tree_ids = ConditionTree::ConditionTreeFactory.match_records(@collection, selection_ids[:ids])
          condition_tree_ids = condition_tree_ids.inverse if selection_ids[:are_excluded]
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
            condition_tree: ConditionTree::ConditionTreeFactory.intersect(
              [
                Utils::QueryStringParser.parse_condition_tree(@collection, args),
                condition_tree_ids
              ]
            )
          )

          @collection.delete(@caller, filter)
        end
      end
    end
  end
end
