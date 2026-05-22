module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Exposes a navigable PaymentOrder <-> Transaction link.
      # Transaction has no native payment_order_id; the relation is mediated by
      # MambuReconciliation (Reconciliation.payment_id + payment_type discriminator).
      # See TwoStepReconciliationFilter for the OneToMany filter rewrite.
      #
      # Install at the datasource level:
      #   @agent.use(
      #     ForestAdminDatasourceMambuPayments::Plugins::Relations::LinkPaymentOrderToTransactions,
      #     {}
      #   )
      class LinkPaymentOrderToTransactions < ForestAdminDatasourceCustomizer::Plugins::Plugin
        ComputedDefinition = ForestAdminDatasourceCustomizer::Decorators::Computed::ComputedDefinition

        PAYMENT_ORDER    = 'MambuPaymentOrder'.freeze
        TRANSACTION      = 'MambuTransaction'.freeze
        FK_NAME          = 'payment_order_id'.freeze
        PAYMENT_TYPE     = 'payment_order'.freeze
        ONE_TO_MANY_NAME = 'transactions'.freeze

        def run(datasource_customizer, _collection_customizer = nil, _options = {})
          unless datasource_customizer
            raise ArgumentError,
                  'LinkPaymentOrderToTransactions must be installed at the datasource level ' \
                  'via @agent.use(plugin, {})'
          end

          datasource_customizer.customize_collection(TRANSACTION) do |c|
            # Virtual column: Transaction has no native payment_order_id.
            # Reverse lookup would require scanning all reconciliations — kept
            # nil per record; only EQUAL/IN filters are rewritten via the
            # TwoStepReconciliationFilter below.
            c.add_field(FK_NAME, ComputedDefinition.new(
                                   column_type: 'String',
                                   dependencies: ['id'],
                                   values: proc { |records, _ctx| records.map { nil } }
                                 ))
            TwoStepReconciliationFilter.install(c,
                                                fk_name: FK_NAME,
                                                payment_type: PAYMENT_TYPE,
                                                target_field: 'id')
          end

          datasource_customizer.customize_collection(PAYMENT_ORDER) do |c|
            c.add_one_to_many_relation(ONE_TO_MANY_NAME, TRANSACTION,
                                       origin_key: FK_NAME,
                                       origin_key_target: 'id')
          end
        end
      end
    end
  end
end
