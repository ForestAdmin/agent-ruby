module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Reciprocal OneToMany on MambuExternalAccount for the native
      # DirectDebitMandate.external_account ManyToOne.
      # Install at the datasource level: @agent.use(plugin, {}).
      class LinkExternalAccountToDirectDebitMandates < OneToManyLinkPlugin
        link host: 'MambuExternalAccount', to: 'MambuDirectDebitMandate',
             name: 'direct_debit_mandates', origin_key: 'external_account_id'
      end
    end
  end
end
