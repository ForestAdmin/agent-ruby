module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Exposes a navigable IncomingPayment <-> ExpectedPayment link.
      # The chain crosses MambuReconciliation twice via the shared transaction:
      #   IP -> Reconciliation(incoming_payment) -> Transaction
      #      -> Reconciliation(expected_payment) -> ExpectedPayment
      # Named `matched_expected_payments` on the IP side to make the transitive
      # (reconciliation-driven) nature explicit — it is not a native FK.
      # See TwoStepCrossReconciliationFilter for the OneToMany filter rewrite.
      #
      # Install at the datasource level:
      #   @agent.use(
      #     ForestAdminDatasourceMambuPayments::Plugins::Relations::LinkIncomingPaymentToExpectedPayments,
      #     {}
      #   )
      class LinkIncomingPaymentToExpectedPayments < ForestAdminDatasourceCustomizer::Plugins::Plugin
        ComputedDefinition = ForestAdminDatasourceCustomizer::Decorators::Computed::ComputedDefinition

        INCOMING_PAYMENT = 'MambuIncomingPayment'.freeze
        EXPECTED_PAYMENT = 'MambuExpectedPayment'.freeze
        FK_NAME          = 'incoming_payment_id'.freeze
        SRC_PAYMENT_TYPE = 'incoming_payment'.freeze
        DST_PAYMENT_TYPE = 'expected_payment'.freeze
        ONE_TO_MANY_NAME = 'matched_expected_payments'.freeze

        def run(datasource_customizer, _collection_customizer = nil, _options = {})
          Plugins::Helpers.require_datasource!(datasource_customizer, self.class)

          datasource_customizer.customize_collection(EXPECTED_PAYMENT) do |c|
            # Virtual column: ExpectedPayment has no native incoming_payment_id.
            # The link goes through two reconciliations sharing a transaction;
            # populating a per-record value would require scanning all
            # reconciliations. Kept nil; only EQUAL/IN filters are rewritten
            # via the TwoStepCrossReconciliationFilter below.
            c.add_field(FK_NAME, ComputedDefinition.new(
                                   column_type: 'String',
                                   dependencies: ['id'],
                                   values: proc { |records, _ctx| records.map { nil } }
                                 ))
            TwoStepCrossReconciliationFilter.install(c,
                                                     fk_name: FK_NAME,
                                                     src_payment_type: SRC_PAYMENT_TYPE,
                                                     dst_payment_type: DST_PAYMENT_TYPE,
                                                     target_field: 'id')
          end

          datasource_customizer.customize_collection(INCOMING_PAYMENT) do |c|
            c.add_one_to_many_relation(ONE_TO_MANY_NAME, EXPECTED_PAYMENT,
                                       origin_key: FK_NAME,
                                       origin_key_target: 'id')
          end
        end
      end
    end
  end
end
