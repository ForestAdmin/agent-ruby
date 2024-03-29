module ForestAdminDatasourceCustomizer
  module Decorators
    module Write
      module UpdateRelations
        class UpdateRelationsCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
          include ForestAdminDatasourceToolkit::Components::Query

          def update(caller, filter, patch)
            # Step 1: Perform the normal update
            if patch.keys.any? { |key| schema[:fields][key].type == 'Column' }
              patch_without_relations = patch.reduce({}) do |carry, (key, value)|
                schema[:fields][key].type == 'Column' ? carry.merge(key => value) : carry
              end

              child_collection.update(caller, filter, patch_without_relations)
            end

            # Step 2: Perform additional updates for relations
            return unless patch.keys.any? { |key| schema[:fields][key].type != 'Column' }

            # Fetch the records that will be updated, to know which relations need to be created/updated
            projection = build_projection(patch)
            records = list(caller, filter, projection)

            # Perform the updates for each relation
            patch.keys
                 .filter { |key| schema[:fields][key].type != 'Column' }
                 .map { |key| create_or_update_relation(caller, records, key, patch[key]) }
          end

          private

          # Build a projection that has enough information to know
          # - which relations need to be created/updated
          # - the values that will be used to build filters to target records
          # - the values that will be used to create/update the relations
          def build_projection(patch)
            projection = Projection.new.with_pks(self)

            patch.each_key do |key|
              field_schema = schema[:fields][key]

              next unless field_schema.type != 'Column'

              relation = datasource.get_collection(field_schema.foreign_collection)

              projection = projection.union(Projection.new.with_pks(relation).nest(prefix: key))
              if field_schema.type == 'ManyToOne'
                projection = projection.union(Projection.new([field_schema.foreign_key_target]).nest(prefix: key))
              end
              if field_schema.type == 'OneToOne'
                projection = projection.union(Projection.new([field_schema.origin_key_target]).nest(prefix: key))
              end
            end

            projection
          end

          def create_or_update_relation(caller, records, key, patch)
            field_schema = schema[:fields][key]
            relation = datasource.get_collection(field_schema.foreign_collection)
            creates = records.filter { |r| !r[key] || r[key].nil? }
            updates = records.filter { |r| r[key] && !r[key].nil? }

            unless creates.empty?
              if field_schema.type == 'ManyToOne'
                # Create many-to-one relations
                sub_record = relation.create(caller, [patch])

                # Set foreign key on the parent records
                condition_tree = ConditionTree::ConditionTreeFactory.match_records(schema, creates)
                parent_patch = { field_schema.foreign_key => sub_record[field_schema.foreign_key_target] }

                update(caller, Filter.new(condition_tree: condition_tree), parent_patch)
              else
                # Create the one-to-one relations that don't already exist
                relation.create(
                  caller,
                  creates.map do |record|
                    patch.merge(field_schema.origin_key => record[field_schema.origin_key_target])
                  end
                )
              end
            end

            # Update the relations that already exist
            return if updates.empty?

            sub_records = updates.map { |record| record[key] }
            condition_tree = ConditionTree::ConditionTreeFactory.match_records(relation, sub_records)

            relation.update(caller, Filter.new(condition_tree: condition_tree), patch)
          end
        end
      end
    end
  end
end
