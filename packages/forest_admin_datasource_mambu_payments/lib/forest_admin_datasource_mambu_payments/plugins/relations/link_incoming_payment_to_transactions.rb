module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Exposes a navigable IncomingPayment <-> Transaction link.
      # Transaction has no native incoming_payment_id; the relation is mediated
      # by MambuReconciliation (Reconciliation.payment_id + payment_type
      # discriminator). See TwoStepReconciliationFilter for the OneToMany filter
      # rewrite.
      #
      # Install at the datasource level:
      #   @agent.use(
      #     ForestAdminDatasourceMambuPayments::Plugins::Relations::LinkIncomingPaymentToTransactions,
      #     {}
      #   )
      class LinkIncomingPaymentToTransactions < ForestAdminDatasourceCustomizer::Plugins::Plugin
        ComputedDefinition = ForestAdminDatasourceCustomizer::Decorators::Computed::ComputedDefinition

        INCOMING_PAYMENT = 'MambuIncomingPayment'.freeze
        TRANSACTION      = 'MambuTransaction'.freeze
        FK_NAME          = 'incoming_payment_id'.freeze
        PAYMENT_TYPE     = 'incoming_payment'.freeze
        ONE_TO_MANY_NAME = 'transactions'.freeze

        def run(datasource_customizer, _collection_customizer = nil, _options = {})
          Plugins::Helpers.require_datasource!(datasource_customizer, self.class)

          datasource_customizer.customize_collection(TRANSACTION) do |c|
            # Virtual column: Transaction has no native incoming_payment_id.
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

          datasource_customizer.customize_collection(INCOMING_PAYMENT) do |c|
            c.add_one_to_many_relation(ONE_TO_MANY_NAME, TRANSACTION,
                                       origin_key: FK_NAME,
                                       origin_key_target: 'id')
          end
        end
      end
    end
  end
end
