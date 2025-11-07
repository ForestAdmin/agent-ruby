require 'active_support/all'
require 'active_support/core_ext/numeric/time'

module ForestAdminDatasourceToolkit
  module Components
    module Query
      class FilterFactory
        include ForestAdminDatasourceToolkit::Schema
        include ForestAdminDatasourceToolkit::Schema::Relations
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

        def self.from_plain_object(json)
          return Filter.new if json.nil? || json.empty?

          Filter.new(
            condition_tree: ConditionTree::ConditionTreeFactory.from_plain_object(
              json['condition_tree'] || nil
            ),
            page: if json['page'].nil?
                    nil
                  else
                    Page.new(offset: json['page']['offset'], limit: json['page']['limit'])
                  end,
            search: json['search'],
            search_extended: json['search_extended'],
            sort: json['sort'].nil? ? nil : Sort.new(json['sort']),
            segment: json['segment']
          )
        end

        def self.get_previous_period_filter(filter, timezone)
          filter.override(condition_tree: filter.condition_tree.replace_leafs do |leaf|
                                            case leaf.operator
                                            when Operators::YESTERDAY
                                              get_previous_period_by_unit(leaf.field, 'Day', timezone)
                                            when Operators::PREVIOUS_WEEK
                                              get_previous_period_by_unit(leaf.field, 'Week', timezone)
                                            when Operators::PREVIOUS_MONTH
                                              get_previous_period_by_unit(leaf.field, 'Month', timezone)
                                            when Operators::PREVIOUS_QUARTER
                                              get_previous_period_by_unit(leaf.field, 'Quarter', timezone)
                                            when Operators::PREVIOUS_YEAR
                                              get_previous_period_by_unit(leaf.field, 'Year', timezone)
                                            when Operators::PREVIOUS_WEEK_TO_DATE
                                              leaf.override(operator: Operators::PREVIOUS_WEEK)
                                            when Operators::PREVIOUS_MONTH_TO_DATE
                                              leaf.override(operator: Operators::PREVIOUS_MONTH)
                                            when Operators::PREVIOUS_QUARTER_TO_DATE
                                              leaf.override(operator: Operators::PREVIOUS_QUARTER)
                                            when Operators::PREVIOUS_YEAR_TO_DATE
                                              leaf.override(operator: Operators::PREVIOUS_YEAR)
                                            when Operators::TODAY
                                              leaf.override(operator: Operators::YESTERDAY)
                                            when Operators::PREVIOUS_X_DAYS
                                              get_previous_x_days_period(leaf, timezone, Operators::PREVIOUS_X_DAYS)
                                            when Operators::PREVIOUS_X_DAYS_TO_DATE
                                              get_previous_x_days_period(leaf, timezone, Operators::PREVIOUS_X_DAYS_TO_DATE)
                                            else
                                              leaf
                                            end
                                          end)
        end

        def self.get_previous_condition_tree(field, start_period, end_period)
          ConditionTreeFactory.intersect([
                                           Nodes::ConditionTreeLeaf.new(field, Operators::GREATER_THAN,
                                                                        start_period.strftime('%Y-%m-%d %H:%M:%S')),
                                           Nodes::ConditionTreeLeaf.new(field, Operators::LESS_THAN,
                                                                        end_period.strftime('%Y-%m-%d %H:%M:%S'))
                                         ])
        end

        # Given a collection and a OneToMany/ManyToMany relation, generate a filter which
        # - match only children of the provided recordId
        # - can apply on the target collection of the relation
        def self.make_foreign_filter(collection, id, relation_name, caller, base_foreign_filter)
          relation = ForestAdminDatasourceToolkit::Utils::Schema.get_to_many_relation(collection, relation_name)
          origin_value = ForestAdminDatasourceToolkit::Utils::Collection.get_value(collection, caller, id,
                                                                                   relation.origin_key_target)

          if relation.is_a?(OneToManySchema)
            origin_tree = Nodes::ConditionTreeLeaf.new(relation.origin_key, Operators::EQUAL, origin_value)
          elsif relation.is_a?(PolymorphicOneToManySchema)
            origin_tree = ConditionTreeFactory.intersect(
              [
                Nodes::ConditionTreeLeaf.new(relation.origin_key, Operators::EQUAL, origin_value),
                Nodes::ConditionTreeLeaf.new(relation.origin_type_field, Operators::EQUAL, relation.origin_type_value)
              ]
            )
          else
            through_collection = collection.datasource.get_collection(relation.through_collection)
            conditions = [
              Nodes::ConditionTreeLeaf.new(relation.origin_key, Operators::EQUAL, origin_value),
              Nodes::ConditionTreeLeaf.new(relation.foreign_key, Operators::PRESENT)
            ]

            # add polymorphic type condition if the through association is polymorphic
            add_polymorphic_condition(conditions, relation)

            through_tree = ConditionTreeFactory.intersect(conditions)
            records = through_collection.list(
              caller,
              Filter.new(condition_tree: through_tree),
              Projection.new([relation.foreign_key])
            )

            origin_tree = Nodes::ConditionTreeLeaf.new(
              relation.foreign_key_target,
              Operators::IN,
              records.map { |record| record[relation.foreign_key] }
            )
          end

          base_foreign_filter.override(condition_tree: ConditionTreeFactory.intersect([base_foreign_filter.condition_tree, origin_tree]))
        end

        def self.get_previous_period_by_unit(field, unit, timezone)
          unit = unit.downcase
          start = "beginning_of_#{unit}"
          end_ = "end_of_#{unit}"
          start_period = Time.now.in_time_zone(timezone).send(:"prev_#{unit}").send(start)
          end_period = Time.now.in_time_zone(timezone).send(:"prev_#{unit}").send(end_)

          get_previous_condition_tree(field, start_period.to_datetime, end_period.to_datetime)
        end

        def self.get_previous_x_days_period(leaf, timezone, operator)
          start_period = Time.now.in_time_zone(timezone).send(:-, 2 * leaf.value.day).beginning_of_day
          end_period = if operator == Operators::PREVIOUS_X_DAYS
                         Time.now.in_time_zone(timezone).send(:-, leaf.value.day).beginning_of_day
                       else
                         Time.now.in_time_zone(timezone).send(:-, leaf.value.day)
                       end

          get_previous_condition_tree(leaf.field, start_period.to_datetime, end_period.to_datetime)
        end

        def self.make_through_filter(collection, id, relation_name, caller, base_foreign_filter)
          relation = collection.schema[:fields][relation_name]
          origin_value = ForestAdminDatasourceToolkit::Utils::Collection.get_value(collection, caller, id, relation.origin_key_target)
          foreign_relation =  ForestAdminDatasourceToolkit::Utils::Collection.get_through_target(collection, relation_name)

          # Optimization for many to many when there is not search/segment (saves one query)
          if foreign_relation && base_foreign_filter.nestable?
            foreign_key = collection.datasource.get_collection(relation.through_collection).schema[:fields][relation.foreign_key]
            base_through_filter = base_foreign_filter.nest(foreign_relation)

            conditions = [
              Nodes::ConditionTreeLeaf.new(relation.origin_key, Operators::EQUAL, origin_value),
              base_through_filter.condition_tree
            ]

            # add polymorphic type condition if the through association is polymorphic
            add_polymorphic_condition(conditions, relation)

            condition_tree = ConditionTreeFactory.intersect(conditions)

            if foreign_key.type == 'Column' && foreign_key.filter_operators.include?(Operators::PRESENT)
              present = Nodes::ConditionTreeLeaf.new(relation.foreign_key, Operators::PRESENT)
              condition_tree = ConditionTreeFactory.intersect([condition_tree, present])
            end

            return base_through_filter.override(condition_tree: condition_tree)
          end

          # Otherwise we have no choice but to call the target collection so that search and segment
          # are correctly apply, and then match ids in the though collection.
          target = collection.datasource.get_collection(relation.foreign_collection)
          records = target.list(
            caller,
            make_foreign_filter(collection, id, relation_name, caller, base_foreign_filter),
            Projection.new([relation.foreign_key_target])
          )

          conditions = [
            # only children of parent
            Nodes::ConditionTreeLeaf.new(relation.origin_key, Operators::EQUAL, origin_value),

            # only the children which match the conditions in baseForeignFilter
            Nodes::ConditionTreeLeaf.new(
              relation.foreign_key,
              Operators::IN,
              records.map { |r| r[relation.foreign_key_target] }
            )
          ]

          # add polymorphic type condition if the through association is polymorphic
          add_polymorphic_condition(conditions, relation)

          Filter.new(condition_tree: ConditionTreeFactory.intersect(conditions))
        end

        def self.add_polymorphic_condition(conditions, relation)
          return conditions unless relation.respond_to?(:origin_type_field) &&
                                   relation.origin_type_field &&
                                   relation.origin_type_value

          conditions << Nodes::ConditionTreeLeaf.new(
            relation.origin_type_field,
            Operators::EQUAL,
            relation.origin_type_value
          )
        end
      end
    end
  end
end
