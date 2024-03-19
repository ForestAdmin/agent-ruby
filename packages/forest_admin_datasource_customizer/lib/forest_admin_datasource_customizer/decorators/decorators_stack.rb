module ForestAdminDatasourceCustomizer
  module Decorators
    class DecoratorsStack
      include ForestAdminDatasourceToolkit::Decorators

      attr_reader :datasource, :schema, :search, :early_computed, :late_computed, :action, :relation, :late_op_emulate,
                  :early_op_emulate, :validation, :sort, :rename_field, :publication

      def initialize(datasource)
        @customizations = []

        last = datasource
        last = DatasourceDecorator.new(last, Empty::EmptyCollectionDecorator)
        last = DatasourceDecorator.new(last, OperatorsEquivalence::OperatorsEquivalenceCollectionDecorator)

        last = @early_computed = DatasourceDecorator.new(last, Computed::ComputeCollectionDecorator)
        last = @early_op_emulate = DatasourceDecorator.new(last, OperatorsEmulate::OperatorsEmulateCollectionDecorator)
        last = DatasourceDecorator.new(last, OperatorsEquivalence::OperatorsEquivalenceCollectionDecorator)
        last = @relation = DatasourceDecorator.new(last, Relation::RelationCollectionDecorator)
        last = @late_computed = DatasourceDecorator.new(last, Computed::ComputeCollectionDecorator)
        last = @late_op_emulate = DatasourceDecorator.new(last, OperatorsEmulate::OperatorsEmulateCollectionDecorator)
        last = DatasourceDecorator.new(last, OperatorsEquivalence::OperatorsEquivalenceCollectionDecorator)

        last = @search = DatasourceDecorator.new(last, Search::SearchCollectionDecorator)
        last = @sort = DatasourceDecorator.new(last, Sort::SortCollectionDecorator)
        last = @action = DatasourceDecorator.new(last, Action::ActionCollectionDecorator)
        last = @schema = DatasourceDecorator.new(last, Schema::SchemaCollectionDecorator)
        last = @validation = DatasourceDecorator.new(last, Validation::ValidationCollectionDecorator)

        last = @publication = Publication::PublicationDatasourceDecorator.new(last)
        last = @rename_field = DatasourceDecorator.new(last, RenameField::RenameFieldCollectionDecorator)
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
        queued_customizations = @customizations.clone
        @customizations = []

        while queued_customizations.length.positive?
          queued_customizations.shift.call
          apply_queued_customizations(logger)
        end
      end
    end
  end
end
