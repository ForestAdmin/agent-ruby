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
            context = build(args)
            context.permissions.can?(:edit, context.collection)

            relation = context.collection.schema[:fields][args[:params]['relation_name']]
            parent_primary_key_values = Utils::Id.unpack_id(context.collection, args[:params]['id'])

            linked_primary_key_values = if (id = args.dig(:params, 'data', 'id'))
                                          Utils::Id.unpack_id(context.child_collection, id)
                                        end

            case relation.type
            when 'ManyToOne'
              update_many_to_one(relation, parent_primary_key_values, linked_primary_key_values, context)
            when 'PolymorphicManyToOne'
              update_polymorphic_many_to_one(relation, parent_primary_key_values, linked_primary_key_values, context)
            when 'OneToOne'
              update_one_to_one(relation, parent_primary_key_values, linked_primary_key_values, context)
            when 'PolymorphicOneToOne'
              update_polymorphic_one_to_one(relation, parent_primary_key_values, linked_primary_key_values, context)
            end

            { content: nil, status: 204 }
          end

          private

          def update_many_to_one(relation, parent_primary_key_values, linked_primary_key_values, context)
            foreign_value = if linked_primary_key_values
                              Collection.get_value(context.child_collection, context.caller, linked_primary_key_values,
                                                   relation.foreign_key_target)
                            end
            fk_owner = ConditionTree::ConditionTreeFactory.match_ids(context.collection, [parent_primary_key_values])
            context.collection.update(context.caller, Filter.new(condition_tree: fk_owner),
                                      { relation.foreign_key => foreign_value })
          end

          def update_polymorphic_many_to_one(relation, parent_primary_key_values, linked_primary_key_values, context)
            foreign_value = if linked_primary_key_values
                              Collection.get_value(
                                context.child_collection,
                                context.caller,
                                linked_primary_key_values,
                                relation.foreign_key_targets[context.child_collection.name]
                              )
                            end

            polymorphic_type = context.child_collection.name.gsub('__', '::')
            fk_owner = ConditionTree::ConditionTreeFactory.match_ids(context.collection, [parent_primary_key_values])
            context.collection.update(
              context.caller,
              Filter.new(condition_tree: fk_owner),
              {
                relation.foreign_key => foreign_value,
                relation.foreign_key_type_field => polymorphic_type
              }
            )
          end

          def update_polymorphic_one_to_one(relation, parent_primary_key_values, linked_primary_key_values, context)
            origin_value = Collection.get_value(context.collection, context.caller, parent_primary_key_values,
                                                relation.origin_key_target)

            break_old_polymorphic_one_to_one_relationship(relation, origin_value, linked_primary_key_values, context)
            create_new_polymorphic_one_to_one_relationship(relation, origin_value, linked_primary_key_values, context)
          end

          def update_one_to_one(relation, parent_primary_key_values, linked_primary_key_values, context)
            origin_value = Collection.get_value(context.collection, context.caller, parent_primary_key_values,
                                                relation.origin_key_target)

            break_old_one_to_one_relationship(relation, origin_value, linked_primary_key_values, context)
            create_new_one_to_one_relationship(relation, origin_value, linked_primary_key_values, context)
          end

          def break_old_polymorphic_one_to_one_relationship(relation, origin_value, linked_primary_key_values, context)
            linked_primary_key_values ||= []

            old_fk_owner_filter = Filter.new(
              condition_tree: ConditionTree::ConditionTreeFactory.intersect(
                [
                  context.permissions.get_scope(context.collection),
                  ConditionTree::Nodes::ConditionTreeBranch.new(
                    'And',
                    [
                      ConditionTree::Nodes::ConditionTreeLeaf.new(
                        relation.origin_key,
                        ConditionTree::Operators::EQUAL,
                        origin_value
                      ),
                      ConditionTree::Nodes::ConditionTreeLeaf.new(
                        relation.origin_type_field,
                        ConditionTree::Operators::EQUAL,
                        context.collection.name.gsub('__', '::')
                      )
                    ]
                  ),
                  # Don't set the new record's field to null
                  # if it's already initialized with the right value
                  ConditionTree::ConditionTreeFactory.match_ids(context.child_collection,
                                                                [linked_primary_key_values]).inverse
                ]
              )
            )

            result = context.child_collection.aggregate(context.caller, old_fk_owner_filter,
                                                        Aggregation.new(operation: 'Count'), 1)
            return unless !(result[0]['value']).nil? && (result[0]['value']).positive?

            # Avoids updating records to null if it's not authorized by the ORM
            # and if there is no record to update (the filter returns no record)

            context.child_collection.update(
              context.caller,
              old_fk_owner_filter,
              { relation.origin_key => nil, relation.origin_type_field => nil }
            )
          end

          def create_new_polymorphic_one_to_one_relationship(relation, origin_value, linked_primary_key_values, context)
            return unless linked_primary_key_values

            new_fk_owner = ConditionTree::ConditionTreeFactory.match_ids(context.child_collection,
                                                                         [linked_primary_key_values])

            context.child_collection.update(
              context.caller,
              Filter.new(
                condition_tree: ConditionTree::ConditionTreeFactory.intersect(
                  [
                    context.permissions.get_scope(context.collection), new_fk_owner
                  ]
                )
              ),
              { relation.origin_key => origin_value,
                relation.origin_type_field => context.collection.name.gsub('__', '::') }
            )
          end

          def break_old_one_to_one_relationship(relation, origin_value, linked_primary_key_values, context)
            linked_primary_key_values ||= []
            old_fk_owner_filter = Filter.new(
              condition_tree: ConditionTree::ConditionTreeFactory.intersect(
                [
                  context.permissions.get_scope(context.collection),
                  ConditionTree::Nodes::ConditionTreeLeaf.new(
                    relation.origin_key,
                    ConditionTree::Operators::EQUAL,
                    origin_value
                  ),
                  # Don't set the new record's field to null
                  # if it's already initialized with the right value
                  ConditionTree::ConditionTreeFactory.match_ids(context.child_collection,
                                                                [linked_primary_key_values]).inverse
                ]
              )
            )

            result = context.child_collection.aggregate(context.caller, old_fk_owner_filter,
                                                        Aggregation.new(operation: 'Count'), 1)
            return unless !(result[0]['value']).nil? && (result[0]['value']).positive?

            # Avoids updating records to null if it's not authorized by the ORM
            # and if there is no record to update (the filter returns no record)

            context.child_collection.update(context.caller, old_fk_owner_filter, { relation.origin_key => nil })
          end

          def create_new_one_to_one_relationship(relation, origin_value, linked_primary_key_values, context)
            return unless linked_primary_key_values

            new_fk_owner = ConditionTree::ConditionTreeFactory.match_ids(context.child_collection,
                                                                         [linked_primary_key_values])

            context.child_collection.update(
              context.caller,
              Filter.new(condition_tree: ConditionTree::ConditionTreeFactory.intersect(
                [
                  context.permissions.get_scope(context.collection),
                  new_fk_owner
                ]
              )),
              { relation.origin_key => origin_value }
            )
          end
        end
      end
    end
  end
end
