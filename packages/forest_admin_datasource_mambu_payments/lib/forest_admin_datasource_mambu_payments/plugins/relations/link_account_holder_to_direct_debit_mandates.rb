module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # AccountHolder <-> DirectDebitMandate, transitive via the external account
      # (DirectDebitMandate.external_account.account_holder_id).
      # Install at the datasource level: @agent.use(plugin, {}).
      class LinkAccountHolderToDirectDebitMandates < HolderLinkPlugin
        link host: 'MambuDirectDebitMandate', name: 'direct_debit_mandates',
             local_fk: 'external_account_id', intermediate: 'MambuExternalAccount',
             import_path: 'external_account:account_holder_id'
      end
    end
  end
end
