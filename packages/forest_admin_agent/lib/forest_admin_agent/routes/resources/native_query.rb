require 'jsonapi-serializers'
require 'active_support/inflector'

module ForestAdminAgent
  module Routes
    module Resources
      class NativeQuery < AbstractAuthenticatedRoute
        include ForestAdminAgent::Builder
        include ForestAdminAgent::Utils
        include ForestAdminDatasourceToolkit::Exceptions
        include ForestAdminDatasourceToolkit::Components::Charts
        include ForestAdminAgent::Routes::QueryHandler

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
          query = args[:params][:query].strip

          # SECURITY: Validate query BEFORE any string substitution to prevent injection
          # via the record_id parameter
          unless args[:params][:connectionName]
            raise ForestAdminAgent::Http::Exceptions::UnprocessableError, 'Missing native query connection attribute'
          end

          @permissions.can_chart?(args[:params])

          # SECURITY FIX: Perform string substitution BEFORE validation to ensure
          # the final query with substituted values is validated
          if args[:params][:record_id]
            # Validate that record_id contains only safe characters (numbers, letters, hyphens, underscores)
            record_id = args[:params][:record_id].to_s
            unless /\A[\w-]+\z/.match?(record_id)
              raise ForestAdminAgent::Http::Exceptions::UnprocessableError,
                    'Invalid record_id format. Only alphanumeric characters, hyphens, and underscores are allowed.'
            end

            query.gsub!('?', record_id)
          end

          # Validate the final query with all substitutions applied
          QueryValidator.valid?(query)

          self.type = args[:params][:type]
          result = execute_query(
            query,
            args[:params][:connectionName],
            @permissions,
            @caller,
            args[:params][:contextVariables]
          )

          { content: Serializer::ForestChartSerializer.serialize(send(:"make_#{@type}", result)) }
        end

        private

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
          return unless result.count

          result = result.first

          raise_error(result, "'value'") unless result.key?(:value)

          ValueChart.new(result[:value] || 0, result[:previous] || nil).serialize
        end

        def make_objective(result)
          return unless result.count

          result = result.first

          raise_error(result, "'value', 'objective'") unless result.key?(:value) || result.key?(:objective)

          ObjectiveChart.new(result[:value] || 0, result[:objective]).serialize
        end

        def make_pie(result)
          return unless result.count

          raise_error(result[0], "'key', 'value'") if !result[0]&.key?(:value) || !result[0]&.key?(:key)

          PieChart.new(result).serialize
        end

        def make_leaderboard(result)
          return unless result.count

          raise_error(result[0], "'key', 'value'") if !result[0]&.key?(:value) || !result[0]&.key?(:key)

          LeaderboardChart.new(result).serialize
        end

        def make_line(result)
          return unless result.count

          result.map! do |result_line|
            raise_error(result_line, "'key', 'value'") if !result_line.key?(:value) || !result_line.key?(:key)

            { label: result_line[:key], values: { value: result_line[:value] } }
          end

          LineChart.new(result).serialize
        end
      end
    end
  end
end
