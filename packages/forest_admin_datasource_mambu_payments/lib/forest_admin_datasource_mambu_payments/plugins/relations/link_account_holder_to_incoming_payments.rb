module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # AccountHolder <-> IncomingPayment, transitive via the internal account
      # (IncomingPayment.internal_account.account_holder_id).
      # Install at the datasource level: @agent.use(plugin, {}).
      class LinkAccountHolderToIncomingPayments < HolderLinkPlugin
        link host: 'MambuIncomingPayment', name: 'incoming_payments',
             local_fk: 'internal_account_id', intermediate: 'MambuInternalAccount',
             import_path: 'internal_account:account_holder_id'
      end
    end
  end
end
