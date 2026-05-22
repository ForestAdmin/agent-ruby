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
      # Only EQUAL/IN are handled (the operators Forest's OneToMany navigation
      # actually uses).
      module TwoStepCrossReconciliationFilter
        Operators           = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
        ConditionTreeLeaf   = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
        ConditionTreeBranch = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch
        Filter              = ForestAdminDatasourceToolkit::Components::Query::Filter
        Projection          = ForestAdminDatasourceToolkit::Components::Query::Projection

        RECONCILIATION = 'MambuReconciliation'.freeze

        # See TwoStepHolderFilter::NO_MATCH_SENTINEL for the rationale.
        NO_MATCH_SENTINEL = '00000000-0000-0000-0000-000000000000'.freeze

        SUPPORTED_OPS = [Operators::EQUAL, Operators::IN].freeze

        def self.install(collection_customizer, fk_name:, src_payment_type:, dst_payment_type:, target_field:)
          SUPPORTED_OPS.each do |operator|
            collection_customizer.replace_field_operator(fk_name, operator) do |value, context|
              src_ids = TwoStepCrossReconciliationFilter.normalize(value, operator)
              next TwoStepCrossReconciliationFilter.no_match(target_field) if src_ids.empty?

              tx_ids = TwoStepCrossReconciliationFilter.resolve_transactions(context, src_ids, src_payment_type)
              next TwoStepCrossReconciliationFilter.no_match(target_field) if tx_ids.empty?

              dst_ids = TwoStepCrossReconciliationFilter.resolve_payments(context, tx_ids, dst_payment_type)
              next TwoStepCrossReconciliationFilter.no_match(target_field) if dst_ids.empty?

              ConditionTreeLeaf.new(target_field, Operators::IN, dst_ids)
            end
          end
        end

        def self.resolve_transactions(context, src_ids, src_payment_type)
          condition = ConditionTreeBranch.new('And', [
                                                ConditionTreeLeaf.new('payment_id', Operators::IN, src_ids),
                                                ConditionTreeLeaf.new('payment_type', Operators::EQUAL,
                                                                      src_payment_type)
                                              ])
          context.datasource.get_collection(RECONCILIATION).list(
            Filter.new(condition_tree: condition),
            Projection.new(['transaction_id'])
          ).filter_map { |r| r['transaction_id'] }.uniq
        end

        def self.resolve_payments(context, tx_ids, dst_payment_type)
          condition = ConditionTreeBranch.new('And', [
                                                ConditionTreeLeaf.new('transaction_id', Operators::IN, tx_ids),
                                                ConditionTreeLeaf.new('payment_type', Operators::EQUAL,
                                                                      dst_payment_type)
                                              ])
          context.datasource.get_collection(RECONCILIATION).list(
            Filter.new(condition_tree: condition),
            Projection.new(['payment_id'])
          ).filter_map { |r| r['payment_id'] }.uniq
        end

        def self.normalize(value, operator)
          values = operator == Operators::IN ? Array(value) : [value]
          values.compact.reject { |v| v.to_s.empty? }.uniq
        end

        def self.no_match(target_field)
          ConditionTreeLeaf.new(target_field, Operators::EQUAL, NO_MATCH_SENTINEL)
        end
      end
    end
  end
end
