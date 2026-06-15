module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Two-step pre-resolution for `internal_account_id` filters on host
      # collections that link to InternalAccount transitively via the array
      # column `InternalAccount.connected_account_ids` (not a scalar FK).
      # Resolves the holder ids to the set of connected_account ids, then
      # rewrites the predicate against a real field on the host collection
      # (`id` for ConnectedAccount, `connected_account_id` for resources
      # scoped by connected account).
      module TwoStepConnectedAccountFilter
        Operators         = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
        ConditionTreeLeaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

        INTERNAL_ACCOUNT = 'MambuInternalAccount'.freeze
        ARRAY_FIELD      = 'connected_account_ids'.freeze
        FK_NAME          = 'internal_account_id'.freeze

        def self.install(collection_customizer, target_field:)
          PivotResolution::SUPPORTED_OPS.each do |operator|
            collection_customizer.replace_field_operator(FK_NAME, operator) do |value, context|
              ia_ids = PivotResolution.normalize(value, operator)
              next PivotResolution.no_match(target_field) if ia_ids.empty?

              ca_ids = PivotResolution.collect(
                context, INTERNAL_ACCOUNT,
                ConditionTreeLeaf.new('id', Operators::IN, ia_ids), ARRAY_FIELD
              )
              next PivotResolution.no_match(target_field) if ca_ids.empty?

              ConditionTreeLeaf.new(target_field, Operators::IN, ca_ids)
            end
          end
        end
      end
    end
  end
end
