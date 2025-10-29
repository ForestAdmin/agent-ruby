require 'jsonapi-serializers'
require 'active_support/inflector'

module ForestAdminAgent
  module Routes
    module Charts
      class Charts < AbstractAuthenticatedRoute
        include ForestAdminAgent::Builder
        include ForestAdminAgent::Utils
        include ForestAdminDatasourceToolkit::Components::Query
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
        include ForestAdminDatasourceToolkit::Components::Charts

        FORMAT = {
          Day: '%d/%m/%Y',
          Week: 'W%V-%G',
          Month: '%b %y',
          Year: '%Y'
        }.freeze

        def setup_routes
          add_route('forest_chart', 'post', '/stats/:collection_name', lambda { |args|
                                                                         handle_request(args)
                                                                       })
          self
        end

        def handle_request(args = {})
          context = build(args)
          context.permissions.can_chart?(args[:params])
          type = validate_and_get_type(args[:params][:type])
          filter = Filter.new(
            condition_tree: ConditionTreeFactory.intersect(
              [
                context.permissions.get_scope(context.collection),
                ForestAdminAgent::Utils::QueryStringParser.parse_condition_tree(
                  context.collection, args
                )
              ]
            )
          )

          filter = inject_context_variables(filter, context, args)

          { content: Serializer::ForestChartSerializer.serialize(send(:"make_#{type}", context, filter, args)) }
        end

        private

        def validate_and_get_type(type)
          chart_types = %w[Value Objective Pie Line Leaderboard]
          unless chart_types.include?(type)
            raise ForestAdminDatasourceToolkit::Exceptions::ForestException, "Invalid Chart type #{type}"
          end

          type.downcase
        end

        def inject_context_variables(filter, context, args)
          user = context.permissions.get_user_data(context.caller.id)
          team = context.permissions.get_team(context.caller.rendering_id)

          context_variables = ForestAdminAgent::Utils::ContextVariables.new(team, user,
                                                                            args[:params][:contextVariables])
          return filter unless args[:params][:filter]

          filter.override(condition_tree: ContextVariablesInjector.inject_context_in_filter(
            filter.condition_tree, context_variables
          ))
        end

        def make_value(context, filter, args)
          value = compute_value(context, filter, args)
          previous_value = nil
          is_and_aggregator = filter.condition_tree&.try(:aggregator) == 'And'
          with_count_previous = filter.condition_tree&.some_leaf(&:use_interval_operator)

          if with_count_previous && !is_and_aggregator
            previous_filter = FilterFactory.get_previous_period_filter(filter, context.caller.timezone)
            previous_value = compute_value(context, previous_filter, args)
          end

          ValueChart.new(value, previous_value).serialize
        end

        def make_objective(context, filter, args)
          ObjectiveChart.new(compute_value(context, filter, args)).serialize
        end

        def make_pie(context, filter, args)
          group_field = args[:params][:groupByFieldName]
          aggregation = Aggregation.new(
            operation: args[:params][:aggregator],
            field: args[:params][:aggregateFieldName],
            groups: group_field ? [{ field: group_field }] : []
          )

          result = context.collection.aggregate(context.caller, filter, aggregation)

          PieChart.new(result.map { |row| { key: row['group'][group_field], value: row['value'] } }).serialize
        end

        def make_line(context, filter, args)
          group_by_field_name = args[:params][:groupByFieldName]
          time_range = args[:params][:timeRange]
          filter_only_with_values = filter.override(
            condition_tree: ConditionTree::ConditionTreeFactory.intersect(
              [
                filter.condition_tree,
                ConditionTree::Nodes::ConditionTreeLeaf.new(group_by_field_name, ConditionTree::Operators::PRESENT)
              ]
            )
          )
          rows = context.collection.aggregate(
            context.caller,
            filter_only_with_values,
            Aggregation.new(
              operation: args[:params][:aggregator],
              field: args[:params][:aggregateFieldName],
              groups: [{ field: group_by_field_name, operation: time_range }]
            )
          )

          values = {}
          rows.each { |row| values[row['group'][group_by_field_name]] = row['value'] }
          dates = values.keys.sort
          current = dates[0]
          last = dates.last
          result = []
          while current <= last
            result << {
              label: current.strftime(FORMAT[time_range.to_sym]),
              values: { value: values[current] || 0 }
            }
            current += 1.send(time_range.downcase.pluralize.to_sym)
          end

          LineChart.new(result).serialize
        end

        def make_leaderboard(context, filter, args)
          field = context.collection.schema[:fields][args[:params][:relationshipFieldName]]

          if field && field.type == 'OneToMany'
            inverse = ForestAdminDatasourceToolkit::Utils::Collection.get_inverse_relation(
              context.collection,
              args[:params][:relationshipFieldName]
            )
            if inverse
              collection = field.foreign_collection
              leaderboard_filter = filter.nest(inverse)
              aggregation = Aggregation.new(
                operation: args[:params][:aggregator],
                field: args[:params][:aggregateFieldName],
                groups: [{ field: "#{inverse}:#{args[:params][:labelFieldName]}" }]
              )
            end
          end

          if field && field.type == 'ManyToMany'
            origin = ForestAdminDatasourceToolkit::Utils::Collection.get_through_origin(
              context.collection,
              args[:params][:relationshipFieldName]
            )
            target = ForestAdminDatasourceToolkit::Utils::Collection.get_through_target(
              context.collection,
              args[:params][:relationshipFieldName]
            )
            if origin && target
              collection = field.through_collection
              leaderboard_filter = filter.nest(origin)
              aggregation = Aggregation.new(
                operation: args[:params][:aggregator],
                field: args[:params][:aggregateFieldName] ? "#{target}:#{args[:params][:aggregateFieldName]}" : nil,
                groups: [{ field: "#{origin}:#{args[:params][:labelFieldName]}" }]
              )
            end
          end

          if collection && leaderboard_filter && aggregation
            rows = context.datasource.get_collection(collection).aggregate(
              context.caller,
              leaderboard_filter,
              aggregation,
              args[:params][:limit]
            )

            result = rows.map do |row|
              {
                key: row['group'][aggregation.groups[0][:field]],
                value: row['value']
              }
            end

            return LeaderboardChart.new(result).serialize
          end

          raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                'Failed to generate leaderboard chart: parameters do not match pre-requisites'
        end

        def compute_value(context, filter, args)
          aggregation = Aggregation.new(operation: args[:params][:aggregator],
                                        field: args[:params][:aggregateFieldName])
          result = context.collection.aggregate(context.caller, filter, aggregation)

          result[0]['value'] || 0
        end
      end
    end
  end
end
