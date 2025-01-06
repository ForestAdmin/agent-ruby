module ForestAdminDatasourceCustomizer
  module Decorators
    module LazyJoin
      class LazyJoinCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Decorators
        include ForestAdminDatasourceToolkit::Components::Query
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

        def list(caller, filter, projection)
          simplified_projection = get_projection_without_useless_joins(projection)
          refined_filter = refine_filter(caller, filter)
          records = child_collection.list(caller, refined_filter, simplified_projection)

          apply_joins_on_records(projection, simplified_projection, records)
        end

        def aggregate(caller, filter, aggregation, limit = nil)
          refined_filter = refine_filter(caller, filter)
          replaced = {}
          refined_aggregation = aggregation.replace_fields do |field_name|
            if useless_join?(field_name.split(':')[0], aggregation.projection)
              new_field_name = get_foreign_key_for_projection(field_name)
              replaced[new_field_name] = field_name

              new_field_name
            else
              field_name
            end
          end

          results = child_collection.aggregate(caller, refined_filter, refined_aggregation, limit)

          apply_joins_on_aggregate_result(aggregation, refined_aggregation, results, replaced)
        end

        def refine_filter(_caller, filter = nil)
          filter&.override(
            condition_tree: filter.condition_tree&.replace_leafs do |leaf|
              if useless_join?(leaf.field.split(':')[0], filter.condition_tree.projection)
                leaf.override(field: get_foreign_key_for_projection(leaf.field))
              else
                leaf
              end
            end
          )
        end

        private

        def get_foreign_key_for_projection(field_name)
          relation_name = field_name.split(':')[0]
          relation_schema = schema[:fields][relation_name]

          relation_schema.foreign_key
        end

        def useless_join?(relation_name, projection)
          relation_schema = schema[:fields][relation_name]
          sub_projection = projection.relations[relation_name]

          relation_schema.type == 'ManyToOne' &&
            sub_projection.size == 1 &&
            sub_projection[0] == relation_schema.foreign_key_target
        end

        def get_projection_without_useless_joins(projection)
          new_projection = Projection.new(projection)

          projection.relations.each do |relation_name, relation_projection|
            next unless useless_join?(relation_name, projection)

            # remove foreign key target from projection
            new_projection.delete("#{relation_name}:#{relation_projection[0]}")

            # add foreign keys to projection
            fk_field = get_foreign_key_for_projection("#{relation_name}:#{relation_projection[0]}")
            new_projection << fk_field
          end

          new_projection
        end

        def apply_joins_on_records(initial_projection, requested_projection, records)
          return records if initial_projection == requested_projection

          projections_to_add = Projection.new(initial_projection.reject do |field|
            requested_projection.include?(field)
          end)
          projections_to_rm = Projection.new(requested_projection.reject { |field| initial_projection.include?(field) })

          records.each do |record|
            # add to record relation:id
            projections_to_add.relations.each do |relation_name, relation_projection|
              relation_schema = schema[:fields][relation_name]

              if relation_schema && relation_schema.type == 'ManyToOne'
                fk_value = record[get_foreign_key_for_projection("#{relation_name}:#{relation_projection[0]}")]
                record[relation_name] = fk_value.nil? ? nil : { relation_projection[0] => fk_value }
              end
            end

            # remove foreign keys
            projections_to_rm.each { |field| record.delete(field) }
          end

          records
        end

        def apply_joins_on_aggregate_result(initial_aggregation, requested_aggregation, results, fields_to_replace)
          return result if initial_aggregation == requested_aggregation

          results.each do |result|
            group = {}
            result['group'].each do |field, value|
              if fields_to_replace.include?(field)
                group[fields_to_replace[field]] = value
              else
                group[field] = value
              end
            end
            result['group'] = group
          end

          results
        end
      end
    end
  end
end
