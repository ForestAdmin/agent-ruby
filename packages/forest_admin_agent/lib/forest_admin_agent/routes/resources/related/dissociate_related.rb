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
            context = build(args)

            parent_primary_key_values = Utils::Id.unpack_id(context.collection, args[:params]['id'], with_key: true)
            is_delete_mode = !args.dig(:params, :delete).nil?

            if is_delete_mode
              context.permissions.can?(:delete, context.child_collection)
            else
              context.permissions.can?(:edit, context.collection)
            end

            filter = get_base_foreign_filter(args, context)
            relation = Schema.get_to_many_relation(context.collection, args[:params]['relation_name'])

            relation_name = args[:params]['relation_name']
            options = {
              relation: relation,
              relation_name: relation_name,
              parent_pk_values: parent_primary_key_values,
              is_delete_mode: is_delete_mode,
              filter: filter
            }

            if ['OneToMany', 'PolymorphicOneToMany'].include?(relation.type)
              dissociate_or_delete_one_to_many(options, context)
            else
              dissociate_or_delete_many_to_many(options, context)
            end

            { content: nil, status: 204 }
          end

          private

          def dissociate_or_delete_one_to_many(options, context)
            foreign_filter = FilterFactory.make_foreign_filter(
              context.collection,
              options[:parent_pk_values],
              options[:relation_name],
              context.caller,
              options[:filter]
            )

            if options[:is_delete_mode]
              context.child_collection.delete(context.caller, foreign_filter)
            else
              patch = if options[:relation].type == 'PolymorphicOneToMany'
                        { options[:relation].origin_key => nil, options[:relation].origin_type_field => nil }
                      else
                        { options[:relation].origin_key => nil }
                      end
              context.child_collection.update(context.caller, foreign_filter, patch)
            end
          end

          def dissociate_or_delete_many_to_many(options, context)
            through_collection = context.datasource.get_collection(options[:relation].through_collection)

            if options[:is_delete_mode]
              # Generate filters _BEFORE_ deleting stuff, otherwise things break.
              foreign_filter = FilterFactory.make_foreign_filter(
                context.collection,
                options[:parent_pk_values],
                options[:relation_name],
                context.caller,
                options[:filter]
              )
              through_filter = FilterFactory.make_through_filter(
                context.collection,
                options[:parent_pk_values],
                options[:relation_name],
                context.caller,
                options[:filter]
              )

              # Delete records from through collection
              through_collection.delete(context.caller, through_filter)

              # Let the datasource crash when:
              # - the records in the foreignCollection are linked to other records in the origin collection
              # - the underlying database/api is not cascading deletes
              context.child_collection.delete(context.caller, foreign_filter)
            else
              through_filter = FilterFactory.make_through_filter(
                context.collection,
                options[:parent_pk_values],
                options[:relation_name],
                context.caller,
                options[:filter]
              )
              through_collection.delete(context.caller, through_filter)
            end
          end

          def get_base_foreign_filter(args, context)
            selection_ids = Utils::Id.parse_selection_ids(context.child_collection, args[:params])
            selected_ids = ConditionTree::ConditionTreeFactory.match_ids(context.child_collection, selection_ids[:ids])

            selected_ids = selected_ids.inverse if selection_ids[:are_excluded]

            if selection_ids[:ids].empty? && !selection_ids[:are_excluded]
              raise ForestAdminDatasourceToolkit::Exceptions::ForestException, 'Expected no empty id list'
            end

            Filter.new(
              condition_tree: ConditionTree::ConditionTreeFactory.intersect(
                [
                  context.permissions.get_scope(context.child_collection),
                  Utils::QueryStringParser.parse_condition_tree(context.child_collection, args),
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
