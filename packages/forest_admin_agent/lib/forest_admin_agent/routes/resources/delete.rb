require 'jsonapi-serializers'

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
          id = Utils::Id.unpack_id(@collection, args[:params]['id'])
          delete_records(args, { ids: [id], are_excluded: false })

          { content: nil, status: 204 }
        end

        def handle_request_bulk(args = {})
          build(args)
          selection_ids = Utils::Id.parse_selection_ids(@collection, args[:params].to_unsafe_h)
          delete_records(args, selection_ids)

          { content: nil, status: 204 }
        end

        def delete_records(_args, selection_ids)
          # TODO: replace by ConditionTreeFactory.matchIds(this.collection.schema, selectionIds.ids)
          condition_tree = OpenStruct.new(field: 'id', operator: 'IN', value: selection_ids[:ids][0])
          condition_tree.inverse if selection_ids[:are_excluded]
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(condition_tree: condition_tree)

          @collection.delete(@caller, filter)
        end
      end
    end
  end
end
