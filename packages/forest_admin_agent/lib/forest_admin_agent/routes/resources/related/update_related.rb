require 'jsonapi-serializers'

module ForestAdminAgent
  module Routes
    module Resources
      module Related
        class UpdateRelated < AbstractRelatedRoute
          include ForestAdminAgent::Builder
          include ForestAdminDatasourceToolkit::Utils
          include ForestAdminDatasourceToolkit::Components::Query
          def setup_routes
            add_route(
              'forest_related_update',
              'put',
              '/:collection_name/:id/relationships/:relation_name',
              ->(args) { handle_request(args) }
            )

            self
          end

          def handle_request(args = {})
            build(args)

            relation = @collection.fields[args[:params]['relation_name']]
            parent_id = Utils::Id.unpack_id(@collection, args[:params]['id'])
            linked_id = if (id = args.dig(:params, :data, :id))
                          Utils::Id.unpack_id(@child_collection, id)
                        end

            if relation.type == 'ManyToOne'
              update_many_to_one(relation, parent_id, linked_id)
            elsif relation.type == 'OneToOne'
              update_one_to_one(relation, parent_id, linked_id)
            end

            { content: nil, status: 204 }
          end

          private

          def update_many_to_one(relation, parent_id, linked_id)
            foreign_value = if linked_id
                              Collection.get_value(@child_collection, @caller, linked_id, relation.foreign_key_target)
                            end
            fk_owner = ConditionTree::ConditionTreeFactory.match_ids(@collection, [parent_id])

            @collection.update(@caller, Filter.new(condition_tree: fk_owner), { relation.foreign_key => foreign_value })
          end

          def update_one_to_one(relation, parent_id, linked_id)
            origin_value = Collection.get_value(@collection, @caller, parent_id, relation.origin_key_target)

            break_old_one_to_one_relationship(nil, relation, origin_value, linked_id)
            create_new_one_to_one_relationship(nil, relation, origin_value, linked_id)
          end

          def break_old_one_to_one_relationship(_scope, relation, origin_value, linked_id)
            linked_id ||= []
            old_fk_owner_filter = Filter.new(
              condition_tree: ConditionTree::ConditionTreeFactory.intersect(
                [
                  ConditionTree::Nodes::ConditionTreeLeaf.new(
                    relation.origin_key,
                    ConditionTree::Operators::EQUAL,
                    origin_value
                  )
                ].push(
                  # Don't set the new record's field to null
                  # if it's already initialized with the right value
                  ConditionTree::ConditionTreeFactory.match_ids(@child_collection, [linked_id]).inverse
                )
              )
            )

            result = @child_collection.aggregate(@caller, old_fk_owner_filter, Aggregation.new(operation: 'Count'), 1)

            return unless (result[0][:value]).positive?

            # Avoids updating records to null if it's not authorized by the ORM
            # and if there is no record to update (the filter returns no record)

            @child_collection.update(@caller, old_fk_owner_filter, { relation.origin_key => nil })
          end

          def create_new_one_to_one_relationship(_scope, relation, origin_value, linked_id)
            return unless linked_id

            new_fk_owner = ConditionTree::ConditionTreeFactory.match_ids(@child_collection, [linked_id])
            @child_collection.update(
              @caller,
              Filter.new(condition_tree: new_fk_owner),
              { relation.origin_key => origin_value }
            )
          end
        end
      end
    end
  end
end
