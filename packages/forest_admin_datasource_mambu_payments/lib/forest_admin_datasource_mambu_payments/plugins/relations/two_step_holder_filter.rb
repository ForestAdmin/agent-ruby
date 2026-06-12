module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Two-step pre-resolution for `account_holder_id` filters on host
      # collections that link to AccountHolder transitively. Default
      # `import_field` would emit a nested leaf the native list rejects;
      # we pre-list the intermediate collection and rewrite as
      # `local_fk IN (ids)`.
      module TwoStepHolderFilter
        Operators         = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
        ConditionTreeLeaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

        def self.install(collection_customizer, fk_name:, local_fk:, intermediate_collection:)
          PivotResolution::SUPPORTED_OPS.each do |operator|
            collection_customizer.replace_field_operator(fk_name, operator) do |value, context|
              holder_ids = PivotResolution.normalize(value, operator)
              next PivotResolution.no_match(local_fk) if holder_ids.empty?

              fk_ids = PivotResolution.collect(
                context, intermediate_collection,
                ConditionTreeLeaf.new(fk_name, Operators::IN, holder_ids), 'id'
              )
              next PivotResolution.no_match(local_fk) if fk_ids.empty?

              ConditionTreeLeaf.new(local_fk, Operators::IN, fk_ids)
            end
          end
        end
      end
    end
  end
end
