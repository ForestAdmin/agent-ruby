module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # OneToMany on MambuIncomingPayment over Event.related_object_id
      # (events emitted for this incoming payment).
      # Install at the datasource level: @agent.use(plugin, {}).
      class LinkIncomingPaymentToEvents < OneToManyLinkPlugin
        link host: 'MambuIncomingPayment', to: 'MambuEvent',
             name: 'events', origin_key: 'related_object_id'
      end
    end
  end
end
