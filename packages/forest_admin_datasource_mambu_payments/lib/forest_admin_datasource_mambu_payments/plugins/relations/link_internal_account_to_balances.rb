module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # InternalAccount <-> Balance, transitive via
      # InternalAccount.connected_account_ids vs Balance.connected_account_id.
      # Install at the datasource level: @agent.use(plugin, {}).
      class LinkInternalAccountToBalances < TwoStepLinkPlugin
        link owner: 'MambuInternalAccount', filtered: 'MambuBalance',
             name: 'balances', foreign_key: 'internal_account_id'

        def install_source_filter(collection)
          TwoStepConnectedAccountFilter.install(collection, target_field: 'connected_account_id')
        end
      end
    end
  end
end
