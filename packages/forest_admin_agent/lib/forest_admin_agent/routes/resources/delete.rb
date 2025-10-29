require 'jsonapi-serializers'
require 'ostruct'

module ForestAdminAgent
  module Routes
    module Resources
      class Delete < AbstractAuthenticatedRoute
        include ForestAdminAgent::Builder
        include ForestAdminDatasourceToolkit::Components::Query
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

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

          context.collection.schema[:fields].each_value do |field_schema|
            next unless ['PolymorphicOneToOne', 'PolymorphicOneToMany'].include?(field_schema.type)

            origin_values = selection_ids[:ids].map do |pk_hash|
              if pk_hash.is_a?(Hash)
                pk_hash[field_schema.origin_key_target]
              else
                pk_names = ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(context.collection)
                index = pk_names.index(field_schema.origin_key_target)
                pk_hash[index] if index
              end
            end

            condition_tree = Nodes::ConditionTreeBranch.new(
              'And',
              [
                Nodes::ConditionTreeLeaf.new(field_schema.origin_key, Operators::IN, origin_values),
                Nodes::ConditionTreeLeaf.new(field_schema.origin_type_field, Operators::EQUAL,
                                             context.collection.name.gsub('__', '::'))
              ]
            )
            filter = Filter.new(condition_tree: condition_tree)
            context.datasource.get_collection(field_schema.foreign_collection)
                   .update(context.caller, filter, { field_schema.origin_key => nil,
                                                     field_schema.origin_type_field => nil })
          end

          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
            condition_tree: ConditionTree::ConditionTreeFactory.intersect(
              [
                Utils::QueryStringParser.parse_condition_tree(context.collection, args),
                condition_tree_ids,
                context.permissions.get_scope(context.collection)
              ]
            )
          )

          context.collection.delete(context.caller, filter)
        end
      end
    end
  end
end
