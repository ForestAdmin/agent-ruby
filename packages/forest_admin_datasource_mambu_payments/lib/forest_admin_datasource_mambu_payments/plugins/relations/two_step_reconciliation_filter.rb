module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Two-step pre-resolution for `payment_order_id` / `incoming_payment_id`
      # / ... virtual filters on Transaction (and other resources that link to
      # payments via the Reconciliation pivot, not via a native FK).
      # Resolves the payment ids to the set of transaction_ids through
      # `Reconciliation.payment_id` + `Reconciliation.payment_type`, then
      # rewrites the predicate against the host's real id field.
      # Only EQUAL/IN are handled (the operators Forest's OneToMany navigation
      # actually uses).
      module TwoStepReconciliationFilter
        Operators           = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
        ConditionTreeLeaf   = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
        ConditionTreeBranch = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch
        Filter              = ForestAdminDatasourceToolkit::Components::Query::Filter
        Projection          = ForestAdminDatasourceToolkit::Components::Query::Projection

        RECONCILIATION = 'MambuReconciliation'.freeze

        # See TwoStepHolderFilter::NO_MATCH_SENTINEL for the rationale.
        NO_MATCH_SENTINEL = '00000000-0000-0000-0000-000000000000'.freeze

        SUPPORTED_OPS = [Operators::EQUAL, Operators::IN].freeze

        def self.install(collection_customizer, fk_name:, payment_type:, target_field:)
          SUPPORTED_OPS.each do |operator|
            collection_customizer.replace_field_operator(fk_name, operator) do |value, context|
              payment_ids = TwoStepReconciliationFilter.normalize(value, operator)
              next TwoStepReconciliationFilter.no_match(target_field) if payment_ids.empty?

              condition = ConditionTreeBranch.new('And', [
                                                    ConditionTreeLeaf.new('payment_id', Operators::IN, payment_ids),
                                                    ConditionTreeLeaf.new('payment_type', Operators::EQUAL,
                                                                          payment_type)
                                                  ])

              tx_ids = context.datasource.get_collection(RECONCILIATION).list(
                Filter.new(condition_tree: condition),
                Projection.new(['transaction_id'])
              ).filter_map { |r| r['transaction_id'] }.uniq

              next TwoStepReconciliationFilter.no_match(target_field) if tx_ids.empty?

              ConditionTreeLeaf.new(target_field, Operators::IN, tx_ids)
            end
          end
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
