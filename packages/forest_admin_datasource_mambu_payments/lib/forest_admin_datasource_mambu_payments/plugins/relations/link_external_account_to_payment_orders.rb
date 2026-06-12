module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Reciprocal OneToMany on MambuExternalAccount for the native
      # PaymentOrder.external_account ManyToOne (receiving account).
      # Install at the datasource level: @agent.use(plugin, {}).
      class LinkExternalAccountToPaymentOrders < OneToManyLinkPlugin
        link host: 'MambuExternalAccount', to: 'MambuPaymentOrder',
             name: 'payment_orders', origin_key: 'receiving_account_id'
      end
    end
  end
end
