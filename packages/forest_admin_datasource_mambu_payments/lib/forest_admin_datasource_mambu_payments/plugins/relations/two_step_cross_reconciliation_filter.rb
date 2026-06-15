module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Resolves "matched payment" filters that cross the Reconciliation pivot
      # twice via the shared transaction. Used when two payment resources only
      # know about each other through reconciliations against the same
      # Transaction (e.g. IncomingPayment <-> ExpectedPayment).
      #
      # Chain (for a `matched_X_id` filter installed on host collection Y):
      #   Reconciliation WHERE payment_id IN [x_ids]    AND payment_type = src
      #     -> transaction_ids
      #   Reconciliation WHERE transaction_id IN [tx_ids] AND payment_type = dst
      #     -> y_ids
      # The predicate is then rewritten as `target_field IN y_ids` on the host.
      module TwoStepCrossReconciliationFilter
        Operators         = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
        ConditionTreeLeaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

        RECONCILIATION = 'MambuReconciliation'.freeze

        def self.install(collection_customizer, fk_name:, src_payment_type:, dst_payment_type:, target_field:)
          PivotResolution::SUPPORTED_OPS.each do |operator|
            collection_customizer.replace_field_operator(fk_name, operator) do |value, context|
              src_ids = PivotResolution.normalize(value, operator)
              next PivotResolution.no_match(target_field) if src_ids.empty?

              tx_ids = TwoStepCrossReconciliationFilter.resolve(context, 'payment_id', src_ids,
                                                                src_payment_type, 'transaction_id')
              next PivotResolution.no_match(target_field) if tx_ids.empty?

              dst_ids = TwoStepCrossReconciliationFilter.resolve(context, 'transaction_id', tx_ids,
                                                                 dst_payment_type, 'payment_id')
              next PivotResolution.no_match(target_field) if dst_ids.empty?

              ConditionTreeLeaf.new(target_field, Operators::IN, dst_ids)
            end
          end
        end

        # One hop across the reconciliation pivot: rows where `where_field IN ids`
        # and `payment_type = type`, projected onto `select_field`.
        def self.resolve(context, where_field, ids, payment_type, select_field)
          PivotResolution.collect(
            context, RECONCILIATION,
            PivotResolution.and_branch(
              ConditionTreeLeaf.new(where_field, Operators::IN, ids),
              ConditionTreeLeaf.new('payment_type', Operators::EQUAL, payment_type)
            ),
            select_field
          )
        end
      end
    end
  end
end
