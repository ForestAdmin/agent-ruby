module ForestAdminDatasourceCustomizer
  module Decorators
    module Relation
      class RelationCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Utils
        include ForestAdminDatasourceToolkit::Components::Query
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes

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
          new_projection = projection.replace(->(field) { rewrite_field(field) }, self).with_pks(self)
          records = child_collection.list(caller, new_filter, new_projection)
          return records if new_projection.equals(projection)

          re_project_in_place(caller, records, projection)

          projection.apply(records)
        end

        def aggregate(caller, filter, aggregation, limit)
          new_filter = refine_filter(caller, filter)

          # No emulated relations are used in the aggregation
          if aggregation.projection.relations.keys.all? { |prefix| !@relations.key?(prefix) }
            return child_collection.aggregate(caller, new_filter, aggregation, limit)
          end

          # Fallback to full emulation.
          aggregation.apply(list(caller, filter, aggregation.projection), caller.timezone, limit)
        end

        protected

        def refine_schema(sub_schema)
          sub_schema[:fields].merge!(@relations)
        end

        #   protected override async refineFilter(
        #     caller: Caller,
        #     filter: PaginatedFilter,
        #   ): Promise<PaginatedFilter> {
        #     return filter?.override({
        #       conditionTree: await filter.conditionTree?.replaceLeafsAsync(
        #         leaf => this.rewriteLeaf(caller, leaf),
        #         this,
        #       ),
        #
        #       // Replace sort in emulated relations to
        #       // - sorting by the fk of the relation for many to one
        #       // - removing the sort altogether for one to one
        #       //
        #       // This is far from ideal, but the best that can be done without taking a major
        #       // performance hit.
        #       // Customers which want proper sorting should enable emulation in the associated
        #       // middleware
        #       sort: filter.sort?.replaceClauses(clause =>
        #         this.rewriteField(clause.field).map(field => ({ ...clause, field })),
        #       ),
        #     });
        #   }
        def refine_filter(caller, filter)
          filter.override({
                            condition_tree: filter.condition_tree.replace_leafs do |leaf|
                                              rewrite_leaf(caller, leaf)
                                            end,
                            sort: filter.sort&.replace_clauses do |clause|
                                    rewrite_field(clause.field).map do |field|
                                      { **clause, field: field }
                                    end
                                  end
                          })
        end

        private

        def relation_with_optional_fields(partial_joint)
          relation = partial_joint.dup
          target = datasource.get_collection(relation[:foreign_collection])

          case relation[:type]
          when 'ManyToOne'
            relation[:foreign_key_target] ||= Schema.primary_keys(target.schema).first
          when 'OneToOne', 'OneToMany'
            relation[:origin_key_target] ||= Schema.primary_keys(schema).first
          when 'ManyToMany'
            relation[:origin_key_target] ||= Schema.primary_keys(schema).first
            relation[:foreign_key_target] ||= Schema.primary_keys(target.schema).first
          end

          relation
        end

        def check_foreign_keys(relation)
          return unless relation[:type] == 'ManyToOne' || relation[:type] == 'ManyToMany'

          check_keys(
            relation[:type] == 'ManyToMany' ? datasource.get_collection(relation[:through_collection]) : self,
            datasource.get_collection(relation[:foreign_collection]),
            relation[:foreign_key],
            relation[:foreign_key_target]
          )
        end

        def check_origin_keys(relation)
          if relation[:type] == 'OneToMany' || relation[:type] == 'OneToOne' || relation[:type] == 'ManyToMany'
            check_keys(
              relation[:type] == 'ManyToMany' ? datasource.get_collection(relation[:through_collection]) : self,
              datasource.get_collection(relation[:foreign_collection]),
              relation[:origin_key],
              relation[:origin_key_target]
            )
          end
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
          schema = schema[:fields][prefix]
          return [field] if schema.type == 'Column'

          relation = datasource.get_collection(schema.foreign_collection)
          result = []

          if !@relations.key?(prefix)
            result = relation.rewrite_field(field[prefix.length + 1..]).map { |sub_field| "#{prefix}:#{sub_field}" }
          elsif schema.type == 'ManyToOne'
            result = [schema.foreign_key]
          elsif schema.type == 'OneToOne' || schema.type == 'OneToMany' || schema.type == 'ManyToMany'
            result = [schema.origin_key_target]
          end

          result
        end

        def rewrite_leaf(caller, leaf)
          prefix = leaf.field.split(':').first
          schema = schema[:fields][prefix]
          return leaf if schema.type == 'Column'

          relation = datasource.get_collection(schema.foreign_collection)
          result = leaf

          if !@relations.key?(prefix)
            result = relation.rewrite_leaf(caller, leaf.unnest).nest(prefix)
          elsif schema.type == 'ManyToOne'
            records = relation.list(
              caller,
              Filter.new(condition_tree: leaf.unnest),
              Projection.new(schema.foreign_key_target)
            )

            result = ConditionTreeLeaf.new(schema.foreign_key, 'In', records.map do |record|
                                                                       record[schema.foreign_key_target]
                                                                     end.uniq)
          elsif schema.type == 'OneToOne'
            records = relation.list(
              caller,
              Filter.new(condition_tree: leaf.unnest),
              Projection.new(schema.origin_key)
            )

            result = ConditionTreeLeaf.new(schema.origin_key_target, 'In', records.map do |record|
                                                                             record[schema.origin_key]
                                                                           end.uniq)
          end

          result
        end

        def re_project_in_place(caller, records, projection)
          projection.relations.each do |prefix, sub_projection|
            re_project_relation_in_place(caller, records, prefix, sub_projection)
          end
        end

        def re_project_relation_in_place(caller, records, name, projection)
          schema = schema[:fields][name]
          association = datasource.get_collection(schema.foreign_collection)

          if !@relations[name]
            association.re_project_in_place(caller, records.map { |r| r[name] }.filter { |fk| !fk.nil? }, projection)
          elsif schema.type == 'ManyToOne'
            ids = records.map { |record| record[schema.foreign_key] }.filter { |fk| !fk.nil? }.uniq
            sub_filter = Filter.new(condition_tree: ConditionTreeLeaf.new(schema.foreign_key_target, 'In', ids))
            sub_records = association.list(caller, sub_filter, projection.union([schema.foreign_key_target]))

            records.each do |record|
              record[name] = sub_records.find { |sr| sr[schema.foreign_key_target] == record[schema.foreign_key] }
            end
          elsif schema.type == 'OneToOne' || schema.type == 'OneToMany'
            ids = records.map { |record| record[schema.origin_key_target] }.filter { |okt| !okt.nil? }.uniq
            sub_filter = Filter.new(condition_tree: ConditionTreeLeaf.new(schema.origin_key, 'In', ids))
            sub_records = association.list(caller, sub_filter, projection.union([schema.origin_key]))

            records.each do |record|
              record[name] = sub_records.find { |sr| sr[schema.origin_key] == record[schema.origin_key_target] }
            end
          end
        end
      end
    end
  end
end
