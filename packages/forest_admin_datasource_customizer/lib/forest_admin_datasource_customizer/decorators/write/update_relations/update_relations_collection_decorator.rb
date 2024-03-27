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
              schema = schema[:fields][key]

              next unless schema.type != 'Column'

              relation = datasource.get_collection(schema.foreign_collection)

              projection = projection.union(Projection.new.with_pks(relation).nest(prefix: key))
              if schema.type == 'ManyToOne'
                projection = projection.union(Projection.new(schema.foreign_key_target).nest(prefix: key))
              end
              if schema.type == 'OneToOne'
                projection = projection.union(Projection.new(schema.origin_key_target).nest(prefix: key))
              end
            end

            projection
          end

          def create_or_update_relation(caller, records, key, patch)
            schema = schema[:fields][key]
            relation = datasource.get_collection(schema.foreign_collection)
            creates = records.filter { |r| !r[key] || r[key].nil? }
            updates = records.filter { |r| r[key] && !r[key].nil? }

            if creates.empty?
              # Create the one-to-one relations that don't already exist
              relation.create(
                caller,
                creates.map { |record| patch.merge(schema.origin_key => record[schema.origin_key_target]) }
              )
            else
              # Create many-to-one relations
              sub_record = relation.create(caller, [patch])

              # Set foreign key on the parent records
              condition_tree = ConditionTree::ConditionTreeFactory.match_records(self.schema, creates)
              parent_patch = { schema.foreign_key => sub_record[schema.foreign_key_target] }

              update(caller, Filter.new(condition_tree: condition_tree), parent_patch)
            end

            # Update the relations that already exist
            return if updates.empty?

            sub_records = updates.map { |record| record[key] }
            condition_tree = ConditionTree::ConditionTreeFactory.match_records(relation.schema, sub_records)

            relation.update(caller, Filter.new(condition_tree: condition_tree), patch)
          end
        end
      end
    end
  end
end
