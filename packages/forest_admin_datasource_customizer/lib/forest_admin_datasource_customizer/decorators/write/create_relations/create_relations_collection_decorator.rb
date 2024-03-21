module ForestAdminDatasourceCustomizer
  module Decorators
    module Write
      module CreateRelations
        class CreateRelationsCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
          include ForestAdminDatasourceToolkit::Components::Query
          include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes
          def create(caller, data)
            # Step 1: Remove all relations from records, and store them in a map
            # Note: the extractRelations method modifies the records array in place!
            records_by_relation = extract_relations(data)

            # Step 2: Create the many-to-one relations, and put the foreign keys in the records
            records_by_relation.each do |key, entries|
              create_many_to_one_relation(caller, data, key, entries) if schema.fields[key].type == 'ManyToOne'
            end

            # Step 3: Create the records
            records_with_pk = child_collection.create(caller, data)

            # Step 4: Create the one-to-one relations
            # Note: the create_one_to_one_relation method modifies the records_with_pk array in place!
            records_by_relation.each do |key, entries|
              create_one_to_one_relation(caller, records_with_pk, key, entries) if schema.fields[key].type == 'OneToOne'
            end

            records_with_pk
          end

          private

          def extract_relations(records)
            records_by_relation = {}

            records.each_with_index do |record, index|
              next if schema.fields[index].type != 'Column'

              record.each do |key, sub_record|
                records_by_relation[index] ||= {}
                records_by_relation[index][key] = sub_record
              end
              records.delete_at(index)
            end

            records_by_relation
          end

          def create_many_to_one_relation(caller, records, key, entries)
            schema = schema[:fields][key]
            relation = datasource.get_collection(schema.foreign_collection)
            creations = entries.filter { |index| !records[index][schema.foreign_key] }
            updates = entries.filter { |index| records[index][schema.foreign_key] }

            #         if (! in_array($schema->getForeignKey(), array_keys($records), true)) {
            #             $relatedRecord = $relation->childCollection->create($caller, $entries);
            #             $records[$schema->getForeignKey()] = $relatedRecord[$schema->getForeignKeyTarget()];
            #         }

            # Create the relations when the fk is not present
            if creations.length.positive?
              # Not sure which behavior is better (we'll go with the first option for now):
              # - create a new record for each record in the original create request
              # - use object-hash to create a single record for each unique subRecord
              sub_records = # const subRecords = creations.map(({ subRecord }) => subRecord);
                creations.map do |index|
                  records[index][key]
                end
              related_records = relation.create(caller, sub_records)

              creations.each do |index|
                records[index][schema.foreign_key] = related_records[index][schema.foreign_key_target]
              end
            end

            #      } else {
            #          $value = $records[$schema->getForeignKey()];
            #          $conditionTree = new ConditionTreeLeaf($schema->getForeignKeyTarget(), Operators::EQUAL, $value);
            #          $relation->childCollection->update($caller, new Filter($conditionTree), $entries);
            #      }
            #  }

            # Update the relations when the fk is present
            updates.each do |index, sub_record|
              value = records[index][schema.foreign_key]
              condition_tree = ConditionTreeLeaf.new(schema.foreign_key_target, 'Equal', value)

              relation.update(caller, Filter.new(condition_tree: condition_tree), sub_record)
            end
          end

          def create_one_to_one_relation(caller, records, key, entries)
            schema = schema[:fields][key]
            relation = datasource.get_collection(schema.foreign_collection)

            # Set origin key in the related record
            sub_records = entries.map do |index, sub_record|
              sub_record[schema.origin_key] = records[index][schema.origin_key_target]
            end
            # sub_records = entries.map
            # { |index, sub_record| sub_record.merge(schema.origin_key => records[index][schema.origin_key_target]) }
            # KEY ORIGIN_KEY_TARGET ????

            relation.create(caller, sub_records)
          end
        end
      end
    end
  end
end
