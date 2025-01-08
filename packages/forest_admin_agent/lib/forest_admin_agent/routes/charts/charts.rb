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

        attr_reader :filter

        FORMAT = {
          Day: '%d/%m/%Y',
          Week: 'W%W-%Y',
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
          build(args)
          @permissions.can_chart?(args[:params])
          @args = args
          self.type = args[:params][:type]
          @filter = Filter.new(
            condition_tree: ConditionTreeFactory.intersect(
              [
                @permissions.get_scope(@collection),
                ForestAdminAgent::Utils::QueryStringParser.parse_condition_tree(
                  @collection, args
                )
              ]
            )
          )

          inject_context_variables

          { content: Serializer::ForestChartSerializer.serialize(send(:"make_#{@type}")) }
        end

        private

        def type=(type)
          chart_types = %w[Value Objective Pie Line Leaderboard]
          unless chart_types.include?(type)
            raise ForestAdminDatasourceToolkit::Exceptions::ForestException, "Invalid Chart type #{type}"
          end

          @type = type.downcase
        end

        def inject_context_variables
          user = @permissions.get_user_data(@caller.id)
          team = @permissions.get_team(@caller.rendering_id)

          context_variables = ForestAdminAgent::Utils::ContextVariables.new(team, user,
                                                                            @args[:params][:contextVariables])
          return unless @args[:params][:filter]

          @filter = @filter.override(condition_tree: ContextVariablesInjector.inject_context_in_filter(
            @filter.condition_tree, context_variables
          ))
        end

        def make_value
          value = compute_value(@filter)
          previous_value = nil
          is_and_aggregator = @filter.condition_tree&.try(:aggregator) == 'And'
          with_count_previous = @filter.condition_tree&.some_leaf(&:use_interval_operator)

          if with_count_previous && !is_and_aggregator
            previous_value = compute_value(FilterFactory.get_previous_period_filter(@filter, @caller.timezone))
          end

          ValueChart.new(value, previous_value).serialize
        end

        def make_objective
          ObjectiveChart.new(compute_value(@filter)).serialize
        end

        def make_pie
          group_field = @args[:params][:groupByFieldName]
          aggregation = Aggregation.new(
            operation: @args[:params][:aggregator],
            field: @args[:params][:aggregateFieldName],
            groups: group_field ? [{ field: group_field }] : []
          )

          result = @collection.aggregate(@caller, @filter, aggregation)

          PieChart.new(result.map { |row| { key: row['group'][group_field], value: row['value'] } }).serialize
        end

        def make_line
          group_by_field_name = @args[:params][:groupByFieldName]
          time_range = @args[:params][:timeRange]
          filter_only_with_values = @filter.override(
            condition_tree: ConditionTree::ConditionTreeFactory.intersect(
              [
                @filter.condition_tree,
                ConditionTree::Nodes::ConditionTreeLeaf.new(group_by_field_name, ConditionTree::Operators::PRESENT)
              ]
            )
          )
          rows = @collection.aggregate(
            @caller,
            filter_only_with_values,
            Aggregation.new(
              operation: @args[:params][:aggregator],
              field: @args[:params][:aggregateField],
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

        def make_leaderboard
          field = @collection.schema[:fields][@args[:params][:relationshipFieldName]]

          if field && field.type == 'OneToMany'
            inverse = ForestAdminDatasourceToolkit::Utils::Collection.get_inverse_relation(
              @collection,
              @args[:params][:relationshipFieldName]
            )
            if inverse
              collection = field.foreign_collection
              filter = @filter.nest(inverse)
              aggregation = Aggregation.new(
                operation: @args[:params][:aggregator],
                field: @args[:params][:aggregateFieldName],
                groups: [{ field: "#{inverse}:#{@args[:params][:labelFieldName]}" }]
              )
            end
          end

          if field && field.type == 'ManyToMany'
            origin = ForestAdminDatasourceToolkit::Utils::Collection.get_through_origin(
              @collection,
              @args[:params][:relationshipFieldName]
            )
            target = ForestAdminDatasourceToolkit::Utils::Collection.get_through_target(
              @collection,
              @args[:params][:relationshipFieldName]
            )
            if origin && target
              collection = field.through_collection
              filter = @filter.nest(origin)
              aggregation = Aggregation.new(
                operation: @args[:params][:aggregator],
                field: @args[:params][:aggregateFieldName] ? "#{target}:#{@args[:params][:aggregateFieldName]}" : nil,
                groups: [{ field: "#{origin}:#{@args[:params][:labelFieldName]}" }]
              )
            end
          end

          if collection && filter && aggregation
            rows = @datasource.get_collection(collection).aggregate(
              @caller,
              filter,
              aggregation,
              @args[:params][:limit]
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

        def compute_value(filter)
          aggregation = Aggregation.new(operation: @args[:params][:aggregator],
                                        field: @args[:params][:aggregateFieldName])
          result = @collection.aggregate(@caller, filter, aggregation)

          result[0]['value'] || 0
        end
      end
    end
  end
end
