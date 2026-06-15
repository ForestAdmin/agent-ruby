module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Reciprocal OneToMany on MambuInternalAccount for the native
      # IncomingPayment.internal_account ManyToOne.
      # Install at the datasource level: @agent.use(plugin, {}).
      class LinkInternalAccountToIncomingPayments < OneToManyLinkPlugin
        link host: 'MambuInternalAccount', to: 'MambuIncomingPayment',
             name: 'incoming_payments', origin_key: 'internal_account_id'
      end
    end
  end
end
