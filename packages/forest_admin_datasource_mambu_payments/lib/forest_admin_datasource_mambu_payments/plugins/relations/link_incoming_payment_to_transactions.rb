module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # IncomingPayment <-> Transaction through the Reconciliation pivot
      # (Reconciliation.payment_id + payment_type = incoming_payment).
      # Install at the datasource level: @agent.use(plugin, {}).
      class LinkIncomingPaymentToTransactions < TwoStepLinkPlugin
        link owner: 'MambuIncomingPayment', filtered: 'MambuTransaction',
             name: 'transactions', foreign_key: 'incoming_payment_id'

        def install_source_filter(collection)
          TwoStepReconciliationFilter.install(collection,
                                              fk_name: 'incoming_payment_id',
                                              payment_type: 'incoming_payment',
                                              target_field: 'id')
        end
      end
    end
  end
end
