module ForestAdminDatasourceCustomizer
  module Decorators
    module Relation
      class RelationCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Exceptions
        include ForestAdminDatasourceToolkit::Utils
        include ForestAdminDatasourceToolkit::Components::Query
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes
        include ForestAdminDatasourceToolkit::Schema

        attr_reader :relations

        def initialize(child_collection, datasource)
          super
          @relations = {}
        end

        def add_relation(name, partial_joint)
          relation = relation_with_optional_fields(partial_joint)
          check_foreign_keys(relation)
          check_origin_keys(relation)

          @relations[name] = relation
          mark_schema_as_dirty
        end

        def list(caller, filter, projection)
          new_filter = refine_filter(caller, filter)
          new_projection = projection.replace { |field| rewrite_field(field) }
          records = child_collection.list(caller, new_filter, new_projection)
          return records if new_projection.equals(projection)

          records = re_project_in_place(caller, records, projection)

          projection.apply(records)
        end

        def aggregate(caller, filter, aggregation, limit = nil)
          new_filter = refine_filter(caller, filter)

          # No emulated relations are used in the aggregation
          if aggregation.projection.relations.keys.all? { |prefix| !@relations.key?(prefix) }
            return child_collection.aggregate(caller, new_filter, aggregation, limit)
          end

          # Fallback to full emulation.
          aggregation.apply(list(caller, filter, aggregation.projection), caller.timezone, limit)
        end

        protected

        def refine_schema(child_schema)
          @relations.each do |name, relation|
            child_schema[:fields][name] = relation
          end

          child_schema
        end

        def refine_filter(caller, filter)
          filter.override({
                            condition_tree: filter.condition_tree&.replace_leafs do |leaf|
                                              rewrite_leaf(caller, leaf)
                                            end,
                            sort: filter.sort&.replace_clauses do |clause|
                              rewrite_field(clause[:field]).map do |field|
                                clause.merge(field: field)
                              end
                            end
                          })
        end

        def relation_with_optional_fields(partial_joint)
          relation = partial_joint.dup
          target = datasource.get_collection(partial_joint[:foreign_collection])

          case relation[:type]
          when 'ManyToOne'
            relation = Relations::ManyToOneSchema.new(
              foreign_key: relation[:foreign_key],
              foreign_key_target: if relation[:foreign_key_target].nil?
                                    ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(target).first
                                  else
                                    relation[:foreign_key_target]
                                  end,
              foreign_collection: relation[:foreign_collection]
            )
          when 'OneToOne'
            relation = Relations::OneToOneSchema.new(
              origin_key: relation[:origin_key],
              origin_key_target: if relation[:origin_key_target].nil?
                                   ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(self).first
                                 else
                                   relation[:origin_key_target]
                                 end,
              foreign_collection: relation[:foreign_collection]
            )
          when 'OneToMany'
            relation = Relations::OneToManySchema.new(
              origin_key: relation[:origin_key],
              origin_key_target: if relation[:origin_key_target].nil?
                                   ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(self).first
                                 else
                                   relation[:origin_key_target]
                                 end,
              foreign_collection: relation[:foreign_collection]
            )
          when 'ManyToMany'
            relation = Relations::ManyToManySchema.new(
              origin_key: relation[:origin_key],
              origin_key_target: if relation[:origin_key_target].nil?
                                   ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(self).first
                                 else
                                   relation[:origin_key_target]
                                 end,
              foreign_key: relation[:foreign_key],
              foreign_key_target: if relation[:foreign_key_target].nil?
                                    ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(target).first
                                  else
                                    relation[:foreign_key_target]
                                  end,
              foreign_collection: relation[:foreign_collection],
              through_collection: relation[:through_collection]
            )
          end

          relation
        end

        def check_foreign_keys(relation)
          return unless relation.type == 'ManyToOne' || relation.type == 'ManyToMany'

          check_keys(
            relation.type == 'ManyToMany' ? datasource.get_collection(relation.through_collection) : self,
            datasource.get_collection(relation.foreign_collection),
            relation.foreign_key,
            relation.foreign_key_target
          )
        end

        def check_origin_keys(relation)
          return unless relation.type == 'OneToMany' || relation.type == 'OneToOne' || relation.type == 'ManyToMany'

          check_keys(
            relation.type == 'ManyToMany' ? datasource.get_collection(relation.through_collection) : datasource.get_collection(relation.foreign_collection),
            self,
            relation.origin_key,
            relation.origin_key_target
          )
        end

        def check_keys(owner, target_owner, key_name, target_name)
          check_column(owner, key_name)
          check_column(target_owner, target_name)

          key = owner.schema[:fields][key_name]
          target = target_owner.schema[:fields][target_name]

          return unless key.column_type != target.column_type

          raise ForestException,
                "Types from '#{owner.name}.#{key_name}' and '#{target_owner.name}.#{target_name}' do not match."
        end

        def check_column(owner, name)
          column = owner.schema[:fields][name]

          raise ForestException, "Column not found: '#{owner.name}.#{name}'" if !column || column.type != 'Column'

          return if column.filter_operators.include?(Operators::IN)

          raise ForestException, "Column does not support the In operator: '#{owner.name}.#{name}'"
        end

        def rewrite_field(field)
          prefix = field.split(':').first
          field_schema = schema[:fields][prefix]

          return [field] if field_schema.type == 'Column' || field_schema.type == 'PolymorphicManyToOne'

          relation = datasource.get_collection(field_schema.foreign_collection)
          result = []

          if !@relations.key?(prefix)
            result = relation.rewrite_field(field[prefix.length + 1..]).map { |sub_field| "#{prefix}:#{sub_field}" }
          elsif field_schema.is_a? Relations::ManyToOneSchema
            result = [field_schema.foreign_key]
          elsif field_schema.is_a?(Relations::OneToOneSchema) ||
                field_schema.is_a?(Relations::OneToManySchema) ||
                field_schema.is_a?(Relations::ManyToManySchema)
            result = [field_schema.origin_key_target]
          end

          result
        end

        def rewrite_leaf(caller, leaf)
          prefix = leaf.field.split(':').first
          field_schema = schema[:fields][prefix]
          return leaf if field_schema.type == 'Column'

          relation = datasource.get_collection(field_schema.foreign_collection)
          result = leaf

          if !@relations.key?(prefix)
            result = relation.rewrite_leaf(caller, leaf.unnest).nest(prefix)
          elsif field_schema.type == 'ManyToOne'
            records = relation.list(
              caller,
              Filter.new(condition_tree: leaf.unnest),
              Projection.new([field_schema.foreign_key_target])
            )

            result = ConditionTreeLeaf.new(field_schema.foreign_key, 'In', records.map do |record|
                                                                             record[field_schema.foreign_key_target]
                                                                           end.uniq)
          elsif field_schema.type == 'OneToOne'
            records = relation.list(
              caller,
              Filter.new(condition_tree: leaf.unnest),
              Projection.new([field_schema.origin_key])
            )

            result = ConditionTreeLeaf.new(field_schema.origin_key_target, 'In', records.map do |record|
                                                                                   record[field_schema.origin_key]
                                                                                 end.uniq)
          end

          result
        end

        def re_project_in_place(caller, records, projection)
          projection.relations.each do |prefix, sub_projection|
            re_project_relation_in_place(caller, records, prefix, sub_projection)
          end

          records
        end

        def re_project_relation_in_place(caller, records, name, projection)
          field_schema = schema[:fields][name]
          association = datasource.get_collection(field_schema.foreign_collection)

          if !@relations[name]
            association.re_project_in_place(caller, records.filter_map { |r| r[name] }, projection)
          elsif field_schema.type == 'ManyToOne'
            ids = records.filter_map { |record| record[field_schema.foreign_key] }.uniq
            sub_filter = Filter.new(condition_tree: ConditionTreeLeaf.new(field_schema.foreign_key_target, 'In', ids))
            sub_records = association.list(caller, sub_filter, projection.union([field_schema.foreign_key_target]))

            records.each do |record|
              record[name] = sub_records.find { |sr| sr[field_schema.foreign_key_target] == record[field_schema.foreign_key] }
            end
          elsif field_schema.type == 'OneToOne' || field_schema.type == 'OneToMany'
            ids = records.filter_map { |record| record[field_schema.origin_key_target] }.uniq
            sub_filter = Filter.new(condition_tree: ConditionTreeLeaf.new(field_schema.origin_key, 'In', ids))
            sub_records = association.list(caller, sub_filter, projection.union([field_schema.origin_key]))

            records.each do |record|
              record[name] = sub_records.find { |sr| sr[field_schema.origin_key] == record[field_schema.origin_key_target] }
            end
          end
        end
      end
    end
  end
end
