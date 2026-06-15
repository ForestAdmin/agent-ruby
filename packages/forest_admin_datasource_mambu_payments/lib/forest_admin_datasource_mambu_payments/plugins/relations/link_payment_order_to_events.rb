module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # OneToMany on MambuPaymentOrder over Event.related_object_id
      # (events emitted for this payment order).
      # Install at the datasource level: @agent.use(plugin, {}).
      class LinkPaymentOrderToEvents < OneToManyLinkPlugin
        link host: 'MambuPaymentOrder', to: 'MambuEvent',
             name: 'events', origin_key: 'related_object_id'
      end
    end
  end
end
