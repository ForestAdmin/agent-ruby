# frozen_string_literal: true

require_relative '../builders/chart_builder'

module ForestAdminDatasourceCustomizer
  module DSL
    # DatasourceHelpers provides Rails-like DSL methods for datasource-level customization
    # These methods are included in DatasourceCustomizer to provide a more idiomatic Ruby API
    module DatasourceHelpers
      # Add a chart at the datasource level with a cleaner syntax
      #
      # @example Simple value chart
      #   chart :total_users do
      #     value 1234
      #   end
      #
      # @example Chart with context
      #   chart :monthly_revenue do |context|
      #     collection = context.datasource.get_collection('orders')
      #     total = calculate_revenue(collection)
      #     value total, previous_total
      #   end
      #
      # @param name [String, Symbol] chart name
      # @param block [Proc] chart definition block
      def chart(name, &block)
        add_chart(name.to_s) do |context, result_builder|
          builder = ChartBuilder.new(context, result_builder)
          builder.instance_eval(&block)
        end
      end

      # Customize a collection with automatic conversion to string
      #
      # @example
      #   collection :users do |c|
      #     c.computed_field :full_name, type: 'String' { }
      #   end
      #
      # @param name [String, Symbol] collection name
      # @param block [Proc] customization block
      def collection(name, &block)
        customize_collection(name.to_s, block)
      end

      # Hide/remove collections from Forest Admin
      #
      # @example
      #   hide_collections :internal_logs, :debug_info
      #
      # @param names [Array<String, Symbol>] collection names to hide
      def hide_collections(*names)
        remove_collection(*names.map(&:to_s))
      end

      # Use a plugin with the datasource
      # (Keeps existing syntax as it's already clean)
      #
      # @example
      #   plugin MyCustomPlugin, option1: 'value'
      #
      # @param plugin_class [Class] plugin class
      # @param options [Hash] plugin options
      def plugin(plugin_class, options = {})
        use(plugin_class, options)
      end
    end
  end
end
