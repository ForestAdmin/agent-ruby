module ForestAdminDatasourceCustomizer
  module Decorators
    class DecoratorsStack
      include ForestAdminDatasourceToolkit::Decorators

      attr_reader :datasource, :schema

      def initialize(datasource)
        last = datasource
        last = DatasourceDecorator.new(last, Empty::EmptyCollectionDecorator)
        last = DatasourceDecorator.new(last, OperatorsEquivalence::OperatorsEquivalenceCollectionDecorator)
        last = DatasourceDecorator.new(last, Search::SearchCollectionDecorator)
        last = @schema = DatasourceDecorator.new(last, Schema::SchemaCollectionDecorator)
        @datasource = last
      end

      def queue_customization(customization)
        @customizations << customization
      end

      # Apply all customizations
      # Plugins may queue new customizations, or call other plugins which will queue customizations.
      #
      # This method will be called recursively and clears the queue at each recursion to ensure
      # that all customizations are applied in the right order.
      def apply_queued_customizations(logger)
        queued_customizations = @customizations.pop
        @customizations = []

        while queued_customizations.length.positive?
          queued_customizations.shift.call(logger)
          apply_queued_customizations(logger)
        end
      end
    end
  end
end
