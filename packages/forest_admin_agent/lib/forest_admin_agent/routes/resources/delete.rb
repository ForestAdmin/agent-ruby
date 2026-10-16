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

          nullify_polymorphic_references(context, filter)
          context.collection.delete(context.caller, filter)
        end

        def nullify_polymorphic_references(context, filter)
          relations = context.collection.schema[:fields].values.select do |field_schema|
            NULLIFIED_POLYMORPHIC_TYPES.include?(field_schema.type) &&
              !(field_schema.respond_to?(:cascade_on_delete) && field_schema.cascade_on_delete)
          end
          return if relations.empty?

          # ponytail: loads every deleted record's keys at once, page it if select-all deletes outgrow memory
          records = context.collection.list(context.caller, filter,
                                            Projection.new(relations.map(&:origin_key_target).uniq))

          relations.each do |field_schema|
            origin_values = records.map { |record| record[field_schema.origin_key_target] }
            next if origin_values.empty?

            condition_tree = Nodes::ConditionTreeBranch.new(
              'And',
              [
                Nodes::ConditionTreeLeaf.new(field_schema.origin_key, Operators::IN, origin_values),
                Nodes::ConditionTreeLeaf.new(field_schema.origin_type_field, Operators::EQUAL,
                                             context.collection.name.gsub('__', '::'))
              ]
            )
            context.datasource.get_collection(field_schema.foreign_collection)
                   .update(context.caller, Filter.new(condition_tree: condition_tree),
                           { field_schema.origin_key => nil, field_schema.origin_type_field => nil })
          end
        end
      end
    end
  end
end
