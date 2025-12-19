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

          # Helper to find the RenameCollectionDatasourceDecorator in the datasource chain
          def find_rename_datasource(_context)
            # Access the top-level datasource from Container which should have all decorators applied
            datasource = ForestAdminAgent::Facades::Container.datasource

            # First, navigate to find the CompositeDatasource
            depth = 0
            composite_class = 'ForestAdminDatasourceCustomizer::CompositeDatasource'
            while datasource && datasource.class.name != composite_class && depth < 50
              break unless datasource.instance_variable_defined?(:@child_datasource)

              datasource = datasource.instance_variable_get(:@child_datasource)

              depth += 1
            end

            # If we found the CompositeDatasource, search in its @datasources array
            if datasource&.class&.name == 'ForestAdminDatasourceCustomizer::CompositeDatasource'
              datasources_array = datasource.instance_variable_get(:@datasources)
              datasources_array&.each_with_index do |ds, _idx|
                # Navigate its child_datasource chain to find RenameCollectionDatasourceDecorator
                current = ds
                depth2 = 0
                while current && depth2 < 20
                  return current if current.respond_to?(:get_class_name_for_polymorphic)

                  break unless current.instance_variable_defined?(:@child_datasource)

                  current = current.instance_variable_get(:@child_datasource)

                  depth2 += 1
                end
              end
            end

            nil
          end

          # Helper to get the class name for polymorphic relations, handling renamed collections
          def get_polymorphic_class_name(context, collection_name)
            rename_ds = find_rename_datasource(context)
            if rename_ds
              rename_ds.get_class_name_for_polymorphic(collection_name)
            else
              collection_name.gsub('__', '::')
            end
          end

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

            polymorphic_type = get_polymorphic_class_name(context, context.child_collection.name)

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
                        get_polymorphic_class_name(context, context.collection.name)
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
                relation.origin_type_field => get_polymorphic_class_name(context, context.collection.name) }
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
