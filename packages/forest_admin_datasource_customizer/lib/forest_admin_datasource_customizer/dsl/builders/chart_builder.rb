# frozen_string_literal: true

module ForestAdminDatasourceCustomizer
  module DSL
    # ChartBuilder provides a fluent DSL for building charts
    #
    # @example Simple value chart
    #   chart :total_revenue do
    #     value 12345
    #   end
    #
    # @example Chart with previous value
    #   chart :monthly_sales do
    #     value 784, 760
    #   end
    #
    # @example Distribution chart
    #   chart :status_breakdown do
    #     distribution({ 'Active' => 150, 'Inactive' => 50 })
    #   end
    class ChartBuilder
      def initialize(context, result_builder)
        @context = context
        @result_builder = result_builder
      end

      # Access the context
      attr_reader :context

      # Return a simple value chart
      # @param current [Numeric] current value
      # @param previous [Numeric] previous value (optional)
      def value(current, previous = nil)
        if previous
          @result_builder.value(current, previous)
        else
          @result_builder.value(current)
        end
      end

      # Return a distribution chart
      # @param data [Hash] distribution data
      # @example
      #   distribution({ 'Category A' => 10, 'Category B' => 20 })
      def distribution(data)
        @result_builder.distribution(data)
      end

      # Return an objective chart
      # @param current [Numeric] current value
      # @param target [Numeric] target value
      # @example
      #   objective 235, 300
      def objective(current, target)
        @result_builder.objective(current, target)
      end

      # Return a percentage chart
      # @param value [Numeric] percentage value
      # @example
      #   percentage 75.5
      def percentage(value)
        @result_builder.percentage(value)
      end

      # Return a time-based chart
      # @param data [Array<Hash>] time series data
      # @example
      #   time_based([
      #     { label: 'Jan', values: { sales: 100 } },
      #     { label: 'Feb', values: { sales: 150 } }
      #   ])
      def time_based(data)
        @result_builder.time_based(data)
      end

      # Return a leaderboard chart
      # @param data [Array<Hash>] leaderboard data
      # @example
      #   leaderboard([
      #     { key: 'User 1', value: 100 },
      #     { key: 'User 2', value: 90 }
      #   ])
      def leaderboard(data)
        @result_builder.leaderboard(data)
      end

      # Smart chart - automatically detects the best chart type
      # @param data [Hash, Array, Numeric] chart data
      # @example
      #   smart 1234
      #   smart({ 'A' => 10, 'B' => 20 })
      def smart(data)
        @result_builder.smart(data)
      end
    end
  end
end
