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
            build(args)

            parent_id = Utils::Id.unpack_id(@collection, args[:params]['id'], with_key: true)
            target_relation_id = Utils::Id.unpack_id(@child_collection, args[:params]['data'][0]['id'], with_key: true)
            relation = Schema.get_to_many_relation(@collection, args[:params]['relation_name'])

            if relation.type == 'OneToMany'
              associate_one_to_many(relation, parent_id, target_relation_id)
            else
              associate_many_to_many(relation, parent_id, target_relation_id)
            end

            { content: nil, status: 204 }
          end

          private

          def associate_one_to_many(relation, parent_id, target_relation_id)
            id = Schema.primary_keys(@child_collection)[0]
            value = Collection.get_value(@child_collection, @caller, target_relation_id, id)
            filter = Filter.new(condition_tree: ConditionTree::Nodes::ConditionTreeLeaf.new(id, 'Equal', value))
            value = Collection.get_value(@collection, @caller, parent_id, relation.origin_key_target)

            @child_collection.update(@caller, filter, { relation.origin_key => value })
          end

          def associate_many_to_many(relation, parent_id, target_relation_id)
            id = Schema.primary_keys(@child_collection)[0]
            foreign_value = Collection.get_value(@child_collection, @caller, target_relation_id, id)
            id = Schema.primary_keys(@collection)[0]
            origin_value = Collection.get_value(@collection, @caller, parent_id, id)
            record = { relation.origin_key => origin_value, relation.foreign_key => foreign_value }

            through_collection = @datasource.collection(relation.through_collection)
            through_collection.create(@caller, record)
          end
        end
      end
    end
  end
end
