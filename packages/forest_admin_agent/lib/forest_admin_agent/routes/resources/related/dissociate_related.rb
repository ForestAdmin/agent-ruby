require 'jsonapi-serializers'

module ForestAdminAgent
  module Routes
    module Resources
      module Related
        class DissociateRelated < AbstractRelatedRoute
          include ForestAdminAgent::Builder
          include ForestAdminDatasourceToolkit::Utils
          include ForestAdminDatasourceToolkit::Components::Query
          def setup_routes
            add_route(
              'forest_related_dissociate',
              'delete',
              '/:collection_name/:id/relationships/:relation_name',
              ->(args) { handle_request(args) }
            )

            self
          end

          def handle_request(args = {})
            build(args)

            parent_id = Utils::Id.unpack_id(@collection, args[:params]['id'], with_key: true)
            is_delete_mode = !args.dig(:params, :delete).nil?

            if is_delete_mode
              @permissions.can?(:delete, @child_collection)
            else
              @permissions.can?(:edit, @collection)
            end

            filter = get_base_foreign_filter(args)
            relation = Schema.get_to_many_relation(@collection, args[:params]['relation_name'])

            if relation.type == 'OneToMany' || relation.type == 'PolymorphicOneToMany'
              dissociate_or_delete_one_to_many(relation, args[:params]['relation_name'], parent_id, is_delete_mode,
                                               filter)
            else
              dissociate_or_delete_many_to_many(relation, args[:params]['relation_name'], parent_id, is_delete_mode,
                                                filter)
            end

            { content: nil, status: 204 }
          end

          private

          def dissociate_or_delete_one_to_many(relation, relation_name, parent_id, is_delete_mode, filter)
            foreign_filter = FilterFactory.make_foreign_filter(@collection, parent_id, relation_name, @caller, filter)

            if is_delete_mode
              @child_collection.delete(@caller, foreign_filter)
            else
              patch = if relation.type == 'PolymorphicOneToMany'
                        { relation.origin_key => nil, relation.origin_type_field => nil }
                      else
                        { relation.origin_key => nil }
                      end
              @child_collection.update(@caller, foreign_filter, patch)
            end
          end

          def dissociate_or_delete_many_to_many(relation, relation_name, parent_id, is_delete_mode, filter)
            through_collection = @datasource.get_collection(relation.through_collection)

            if is_delete_mode
              # Generate filters _BEFORE_ deleting stuff, otherwise things break.
              foreign_filter = FilterFactory.make_foreign_filter(@collection, parent_id, relation_name, @caller, filter)
              through_filter = FilterFactory.make_through_filter(@collection, parent_id, relation_name, @caller, filter)

              # Delete records from through collection
              through_collection.delete(@caller, through_filter)

              # Let the datasource crash when:
              # - the records in the foreignCollection are linked to other records in the origin collection
              # - the underlying database/api is not cascading deletes
              @child_collection.delete(@caller, foreign_filter)
            else
              through_filter = FilterFactory.make_through_filter(@collection, parent_id, relation_name, @caller, filter)
              through_collection.delete(@caller, through_filter)
            end
          end

          def get_base_foreign_filter(args)
            selection_ids = Utils::Id.parse_selection_ids(@child_collection, args[:params])
            selected_ids = ConditionTree::ConditionTreeFactory.match_ids(@child_collection, selection_ids[:ids])

            selected_ids = selected_ids.inverse if selection_ids[:are_excluded]

            if selection_ids[:ids].empty? && !selection_ids[:are_excluded]
              raise ForestAdminDatasourceToolkit::Exceptions::ForestException, 'Expected no empty id list'
            end

            Filter.new(
              condition_tree: ConditionTree::ConditionTreeFactory.intersect(
                [
                  @permissions.get_scope(@child_collection),
                  Utils::QueryStringParser.parse_condition_tree(@child_collection, args),
                  selected_ids
                ]
              )
            )
          end
        end
      end
    end
  end
end
