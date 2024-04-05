module ForestAdminDatasourceCustomizer
  module Decorators
    module Write
      module CreateRelations
        class CreateRelationsCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
          include ForestAdminDatasourceToolkit::Components::Query
          include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
          include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes
          def create(caller, data)
            # Step 1: Remove all relations from records, and store them in a map
            # Note: the extractRelations method modifies the records array in place!
            records_by_relation = extract_relations(data)

            # Step 2: Create the many-to-one relations, and put the foreign keys in the records
            records_by_relation.each do |key, entries|
              create_many_to_one_relation(caller, data, key, entries) if schema[:fields][key].type == 'ManyToOne'
            end

            # Step 3: Create the records
            records_with_pk = child_collection.create(caller, data)

            # Step 4: Create the one-to-one relations
            # Note: the create_one_to_one_relation method modifies the records_with_pk array in place!
            records_by_relation.each do |key, entries|
              if schema[:fields][key].type == 'OneToOne'
                create_one_to_one_relation(caller, records_with_pk, key, entries)
              end
            end

            records_with_pk
          end

          private

          def extract_relations(record)
            records_by_relation = {}

            record.each do |key, value|
              next unless schema[:fields][key].type != 'Column'

              value.each do |sub_key, sub_record|
                records_by_relation[key] ||= {}
                records_by_relation[key][sub_key] = sub_record
              end
              record.delete(key)
            end

            records_by_relation
          end

          def create_many_to_one_relation(caller, records, key, entries)
            field_schema = schema[:fields][key]
            relation = datasource.get_collection(field_schema.foreign_collection)

            if records.key?(field_schema.foreign_key)
              value = records[field_schema.foreign_key]
              condition_tree = ConditionTreeLeaf.new(field_schema.foreign_key_target, Operators::EQUAL, value)
              relation.update(caller, Filter.new(condition_tree: condition_tree), entries)
            else
              related_record = relation.create(caller, entries)
              records[field_schema.foreign_key] = related_record[field_schema.foreign_key_target]
            end
          end

          def create_one_to_one_relation(caller, records, key, entries)
            field_schema = schema[:fields][key]
            relation = datasource.get_collection(field_schema.foreign_collection)

            relation.create(caller, entries.merge(field_schema.origin_key => records[field_schema.origin_key_target]))
          end
        end
      end
    end
  end
end
