module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Two-step pre-resolution for `payment_order_id` / `incoming_payment_id`
      # / ... virtual filters on Transaction (and other resources that link to
      # payments via the Reconciliation pivot, not via a native FK).
      # Resolves the payment ids to the set of transaction_ids through
      # `Reconciliation.payment_id` + `Reconciliation.payment_type`, then
      # rewrites the predicate against the host's real id field.
      module TwoStepReconciliationFilter
        Operators         = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
        ConditionTreeLeaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

        RECONCILIATION = 'MambuReconciliation'.freeze

        def self.install(collection_customizer, fk_name:, payment_type:, target_field:)
          PivotResolution::SUPPORTED_OPS.each do |operator|
            collection_customizer.replace_field_operator(fk_name, operator) do |value, context|
              payment_ids = PivotResolution.normalize(value, operator)
              next PivotResolution.no_match(target_field) if payment_ids.empty?

              tx_ids = PivotResolution.collect(
                context, RECONCILIATION,
                PivotResolution.and_branch(
                  ConditionTreeLeaf.new('payment_id', Operators::IN, payment_ids),
                  ConditionTreeLeaf.new('payment_type', Operators::EQUAL, payment_type)
                ),
                'transaction_id'
              )
              next PivotResolution.no_match(target_field) if tx_ids.empty?

              ConditionTreeLeaf.new(target_field, Operators::IN, tx_ids)
            end
          end
        end
      end
    end
  end
end
