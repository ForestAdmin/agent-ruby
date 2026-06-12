module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # OneToMany on MambuIncomingPayment over Return.related_payment_id.
      # Install at the datasource level: @agent.use(plugin, {}).
      class LinkIncomingPaymentToReturns < OneToManyLinkPlugin
        link host: 'MambuIncomingPayment', to: 'MambuReturn',
             name: 'returns', origin_key: 'related_payment_id'
      end
    end
  end
end
