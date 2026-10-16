require 'jsonapi-serializers'
require 'ostruct'

module ForestAdminAgent
  module Routes
    module Resources
      class Delete < AbstractAuthenticatedRoute
        include ForestAdminAgent::Builder
        include ForestAdminDatasourceToolkit::Components::Query
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
        include ForestAdminAgent::Routes::QueryHandler

        NULLIFIED_POLYMORPHIC_TYPES = %w[PolymorphicOneToOne PolymorphicOneToMany].freeze

        def setup_routes
          add_route('forest_delete_bulk', 'delete', '/:collection_name', ->(args) { handle_request_bulk(args) })
          add_route('forest_delete', 'delete', '/:collection_name/:id', ->(args) { handle_request(args) })

          self
        end

        def handle_request(args = {})
          context = build(args)
          context.permissions.can?(:delete, context.collection)
          primary_key_values = Utils::Id.unpack_id(context.collection, args[:params]['id'], with_key: true)
          delete_records(args, { ids: [primary_key_values], are_excluded: false }, context)

          { content: nil, status: 204 }
        end

        def handle_request_bulk(args = {})
          context = build(args)
          context.permissions.can?(:delete, context.collection)
          selection_ids = Utils::Id.parse_selection_ids(context.collection, args[:params], with_key: true)
          delete_records(args, selection_ids, context)

          { content: nil, status: 204 }
        end

        def delete_records(args, selection_ids, context)
          condition_tree_ids = ConditionTree::ConditionTreeFactory.match_records(context.collection,
                                                                                 selection_ids[:ids])
          condition_tree_ids = condition_tree_ids.inverse if selection_ids[:are_excluded]

          filter = build_context_filter(context.collection, args, context.permissions, context.caller)
          filter = filter.override(
            condition_tree: ConditionTree::ConditionTreeFactory.intersect([filter.condition_tree, condition_tree_ids])
          )

          relations = nullified_polymorphic_relations(context.collection)
          # ponytail: loads every deleted record's keys at once, page it if select-all deletes outgrow memory
          records = if relations.any?
                      context.collection.list(context.caller, filter,
                                              Projection.new(relations.map(&:origin_key_target).uniq))
                    end

          context.collection.delete(context.caller, filter)
          relations.each { |relation| nullify_polymorphic_references(context, relation, records) }
        end

        def nullified_polymorphic_relations(collection)
          collection.schema[:fields].values.select do |field_schema|
            NULLIFIED_POLYMORPHIC_TYPES.include?(field_schema.type) &&
              !(field_schema.respond_to?(:cascade_on_delete) && field_schema.cascade_on_delete)
          end
        end

        def nullify_polymorphic_references(context, relation, records)
          origin_values = records.map { |record| record[relation.origin_key_target] }
          return if origin_values.empty?

          condition_tree = Nodes::ConditionTreeBranch.new(
            'And',
            [
              Nodes::ConditionTreeLeaf.new(relation.origin_key, Operators::IN, origin_values),
              Nodes::ConditionTreeLeaf.new(relation.origin_type_field, Operators::EQUAL,
                                           context.collection.name.gsub('__', '::'))
            ]
          )
          context.datasource.get_collection(relation.foreign_collection)
                 .update(context.caller, Filter.new(condition_tree: condition_tree),
                         { relation.origin_key => nil, relation.origin_type_field => nil })
        end
      end
    end
  end
end
