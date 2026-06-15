module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # IncomingPayment <-> ExpectedPayment matched through two reconciliations
      # sharing a transaction (cross-pivot resolution).
      # Install at the datasource level: @agent.use(plugin, {}).
      class LinkIncomingPaymentToExpectedPayments < TwoStepLinkPlugin
        link owner: 'MambuIncomingPayment', filtered: 'MambuExpectedPayment',
             name: 'matched_expected_payments', foreign_key: 'incoming_payment_id'

        def install_source_filter(collection)
          TwoStepCrossReconciliationFilter.install(collection,
                                                   fk_name: 'incoming_payment_id',
                                                   src_payment_type: 'incoming_payment',
                                                   dst_payment_type: 'expected_payment',
                                                   target_field: 'id')
        end
      end
    end
  end
end
