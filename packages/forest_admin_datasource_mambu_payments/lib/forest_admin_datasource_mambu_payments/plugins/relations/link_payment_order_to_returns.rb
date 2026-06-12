module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # OneToMany on MambuPaymentOrder over Return.related_payment_id.
      # Install at the datasource level: @agent.use(plugin, {}).
      class LinkPaymentOrderToReturns < OneToManyLinkPlugin
        link host: 'MambuPaymentOrder', to: 'MambuReturn',
             name: 'returns', origin_key: 'related_payment_id'
      end
    end
  end
end
