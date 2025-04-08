module ForestAdminDatasourceCustomizer
  module Decorators
    class DecoratorsStack
      include ForestAdminDatasourceToolkit::Decorators

      attr_reader :datasource, :schema, :search, :early_computed, :late_computed, :action, :relation, :late_op_emulate,
                  :early_op_emulate, :validation, :sort, :rename_field, :publication, :write, :chart, :hook, :segment,
                  :binary, :override, :lazy_join

      def initialize(datasource)
        @customizations = []
        @applied_customizations = []
        init_stack(datasource)
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

      def reload!(datasource, logger)
        backup = backup_stack
        @customizations = @applied_customizations.dup
        @applied_customizations = []

        begin
          init_stack(datasource)
          apply_queued_customizations(logger)
          logger.log('Debug', 'Reloading customizations')
        rescue StandardError => e
          logger.log('Error', "Error while reloading customizations: #{e.message}, restoring previous state")
          restore_stack(backup)
          raise e
        end
      end

      private

      def init_stack(datasource)
        last = datasource
        last = @override = DatasourceDecorator.new(last, Override::OverrideCollectionDecorator)
        last = DatasourceDecorator.new(last, Empty::EmptyCollectionDecorator)
        last = DatasourceDecorator.new(last, OperatorsEquivalence::OperatorsEquivalenceCollectionDecorator)

        last = @early_computed = DatasourceDecorator.new(last, Computed::ComputeCollectionDecorator)
        last = @early_op_emulate = DatasourceDecorator.new(last, OperatorsEmulate::OperatorsEmulateCollectionDecorator)
        last = DatasourceDecorator.new(last, OperatorsEquivalence::OperatorsEquivalenceCollectionDecorator)
        last = @relation = DatasourceDecorator.new(last, Relation::RelationCollectionDecorator)
        # lazy join is just before relation, to avoid relations to do useless stuff
        last = @lazy_join = DatasourceDecorator.new(last, LazyJoin::LazyJoinCollectionDecorator)
        last = @late_computed = DatasourceDecorator.new(last, Computed::ComputeCollectionDecorator)
        last = @late_op_emulate = DatasourceDecorator.new(last, OperatorsEmulate::OperatorsEmulateCollectionDecorator)
        last = DatasourceDecorator.new(last, OperatorsEquivalence::OperatorsEquivalenceCollectionDecorator)

        last = @search = DatasourceDecorator.new(last, Search::SearchCollectionDecorator)
        last = @segment = DatasourceDecorator.new(last, Segment::SegmentCollectionDecorator)
        last = @sort = DatasourceDecorator.new(last, Sort::SortCollectionDecorator)

        last = @chart = Chart::ChartDatasourceDecorator.new(last)
        last = @action = DatasourceDecorator.new(last, Action::ActionCollectionDecorator)
        last = @schema = DatasourceDecorator.new(last, Schema::SchemaCollectionDecorator)
        last = @write = Write::WriteDatasourceDecorator.new(last)
        last = @hook = DatasourceDecorator.new(last, Hook::HookCollectionDecorator)
        last = @validation = DatasourceDecorator.new(last, Validation::ValidationCollectionDecorator)
        last = @binary = DatasourceDecorator.new(last, Binary::BinaryCollectionDecorator)

        last = @publication = Publication::PublicationDatasourceDecorator.new(last)
        last = @rename_field = DatasourceDecorator.new(last, RenameField::RenameFieldCollectionDecorator)
        @datasource = last
      end

      def backup_stack
        instance_variables.each_with_object({}) do |var, hash|
          hash[var] = instance_variable_get(var)
        end
      end

      def restore_stack(backup)
        backup.each do |var, value|
          instance_variable_set(var, value)
        end
      end
    end
  end
end
