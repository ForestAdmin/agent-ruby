require 'jsonapi-serializers'

module ForestAdminAgent
  module Routes
    module Resources
      module Related
        class AssociateRelated < AbstractRelatedRoute
          include ForestAdminAgent::Builder
          include ForestAdminDatasourceToolkit::Utils
          include ForestAdminDatasourceToolkit::Components::Query

          def setup_routes
            add_route(
              'forest_related_associate',
              'post',
              '/:collection_name/:id/relationships/:relation_name',
              ->(args) { handle_request(args) }
            )

            self
          end

          def handle_request(args = {})
            context = build(args)
            context.permissions.can?(:edit, context.collection)

            parent_primary_key_values = Utils::Id.unpack_id(context.collection, args[:params]['id'], with_key: true)
            target_primary_key_values = Utils::Id.unpack_id(context.child_collection, args[:params]['data'][0]['id'],
                                                            with_key: true)
            relation = Schema.get_to_many_relation(context.collection, args[:params]['relation_name'])

            case relation.type
            when 'OneToMany'
              associate_one_to_many(relation, parent_primary_key_values, target_primary_key_values, context)
            when 'ManyToMany'
              associate_many_to_many(relation, parent_primary_key_values, target_primary_key_values, context)
            when 'PolymorphicOneToMany'
              associate_polymorphic_one_to_many(relation, parent_primary_key_values, target_primary_key_values, context)
            end

            { content: nil, status: 204 }
          end

          private

          def associate_one_to_many(relation, parent_primary_key_values, target_primary_key_values, context)
            id = Schema.primary_keys(context.child_collection)[0]
            value = Collection.get_value(context.child_collection, context.caller, target_primary_key_values, id)
            filter = Filter.new(
              condition_tree: ConditionTree::ConditionTreeFactory.intersect(
                [
                  ConditionTree::Nodes::ConditionTreeLeaf.new(id, 'Equal', value),
                  context.permissions.get_scope(context.collection)
                ]
              )
            )
            value = Collection.get_value(context.collection, context.caller, parent_primary_key_values,
                                         relation.origin_key_target)

            context.child_collection.update(context.caller, filter, { relation.origin_key => value })
          end

          def associate_polymorphic_one_to_many(relation, parent_primary_key_values, target_primary_key_values, context)
            id = Schema.primary_keys(context.child_collection)[0]
            value = Collection.get_value(context.child_collection, context.caller, target_primary_key_values, id)
            filter = Filter.new(
              condition_tree: ConditionTree::ConditionTreeFactory.intersect(
                [
                  ConditionTree::Nodes::ConditionTreeLeaf.new(id, 'Equal', value),
                  context.permissions.get_scope(context.collection)
                ]
              )
            )

            value = Collection.get_value(context.collection, context.caller, parent_primary_key_values,
                                         relation.origin_key_target)

            context.child_collection.update(
              context.caller,
              filter,
              { relation.origin_key => value, relation.origin_type_field => context.collection.name.gsub('__', '::') }
            )
          end

          def associate_many_to_many(relation, parent_primary_key_values, target_primary_key_values, context)
            id = Schema.primary_keys(context.child_collection)[0]
            foreign_value = Collection.get_value(context.child_collection, context.caller, target_primary_key_values,
                                                 id)
            id = Schema.primary_keys(context.collection)[0]
            origin_value = Collection.get_value(context.collection, context.caller, parent_primary_key_values, id)
            record = { relation.origin_key => origin_value, relation.foreign_key => foreign_value }

            through_collection = context.datasource.get_collection(relation.through_collection)
            through_collection.create(context.caller, record)
          end
        end
      end
    end
  end
end
