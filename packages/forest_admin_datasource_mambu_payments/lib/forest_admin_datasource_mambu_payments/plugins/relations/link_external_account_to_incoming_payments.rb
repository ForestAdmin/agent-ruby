module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Reciprocal OneToMany on MambuExternalAccount for the native
      # IncomingPayment.external_account ManyToOne.
      # Install at the datasource level: @agent.use(plugin, {}).
      class LinkExternalAccountToIncomingPayments < OneToManyLinkPlugin
        link host: 'MambuExternalAccount', to: 'MambuIncomingPayment',
             name: 'incoming_payments', origin_key: 'external_account_id'
      end
    end
  end
end
