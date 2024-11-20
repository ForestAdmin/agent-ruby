require 'jsonapi-serializers'
require 'active_support/inflector'

module ForestAdminAgent
  module Routes
    module Resources
      class NativeQuery < AbstractAuthenticatedRoute
        include ForestAdminAgent::Builder
        include ForestAdminAgent::Utils
        include ForestAdminDatasourceToolkit::Components::Query
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
        include ForestAdminDatasourceToolkit::Components::Charts

        def setup_routes
          add_route(
            'forest_native_query',
            'post',
            '/_internal/native_query',
            lambda { |args|
              handle_request(args)
            }
          )

          self
        end

        def handle_request(args = {})
          build(args)
          @query = args[:params][:query].strip
          @args = args

          QueryValidator.valid?(@query)
          # TODO: update permission checker
          # @permissions.can_chart?(args[:params])

          self.type = @args[:params][:type]
          inject_context_variables

          @query.gsub!('?', @args[:params][:record_id].to_s) if @args[:params][:record_id]

          root_datasource = AgentFactory.instance.customizer.get_datasource(@args[:params][:datasource])
          result = root_datasource.execute_native_query(@query)

          { content: Serializer::ForestChartSerializer.serialize(send(:"make_#{@type}", result)) }
        end

        private

        def inject_context_variables
          user = @permissions.get_user_data(@caller.id)
          team = @permissions.get_team(@caller.rendering_id)
          context_variables = ContextVariables.new(team, user, @args[:params][:contextVariables])

          @query = ContextVariablesInjector.inject_context_in_value(@query, context_variables)
        end

        def type=(type)
          chart_types = %w[Value Objective Pie Line Leaderboard]
          unless chart_types.include?(type)
            raise ForestAdminDatasourceToolkit::Exceptions::ForestException, "Invalid Chart type #{type}"
          end

          @type = type.downcase
        end

        def raise_error(result, key_names)
          raise ForestException,
                "The result columns must be named #{key_names} instead of '#{result.keys.join("', '")}'"
        end

        def make_value(result)
          # not sure if it's useful
          return unless result.count

          # TODO: check the result format with MYSQL2 ADAPTER
          # result_line = ForestLiana::AdapterHelper.format_live_query_result(result, type)
          result = result.first

          raise_error(result, "'value'") unless result.key?('value')

          ValueChart.new(result['value'] || 0, result['previous'] || 0).serialize
        end

        def make_objective(result)
          return unless result.count

          # TODO: check the result format with MYSQL2 ADAPTER
          # result_line = ForestLiana::AdapterHelper.format_live_query_result(result, type)
          result = result.first

          raise_error(result, "'value', 'objective'") unless result.key?('value') || result.key?('objective')

          ObjectiveChart.new(result['value'] || 0, result['objective']).serialize
        end

        def make_pie(result)
          return unless result.count

          # TODO: check the result format with MYSQL2 ADAPTER
          # result_line = ForestLiana::AdapterHelper.format_live_query_result(result, type)

          result.each do |result_line|
            raise_error(result_line, "'key', 'value'") if !result_line.key?('value') || !result_line.key?('key')
          end

          PieChart.new(result).serialize
        end

        def make_leaderboard(result)
          return unless result.count

          # TODO: check the result format with MYSQL2 ADAPTER
          # result_line = ForestLiana::AdapterHelper.format_live_query_result(result, type)

          result.each do |result_line|
            raise_error(result_line, "'key', 'value'") if !result_line.key?('value') || !result_line.key?('key')
          end

          LeaderboardChart.new(result).serialize
        end

        def make_line(result)
          return unless result.count

          # TODO: check the result format with MYSQL2 ADAPTER
          # result_line = ForestLiana::AdapterHelper.format_live_query_result(result, type)

          result.map do |result_line|
            raise_error(result_line, "'key', 'value'") if !result_line.key?('value') || !result_line.key?('key')

            { label: result_line['key'], values: { value: result_line['value'] } }
          end

          LineChart.new(result).serialize
        end
      end
    end
  end
end
