module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # PaymentOrder <-> AccountHolder of the receiving external account.
      # Named `receiving_account_holder` to disambiguate from the originating side.
      # Install at the datasource level: @agent.use(plugin, {}).
      class LinkPaymentOrderToReceivingAccountHolder < HolderLinkPlugin
        link host: 'MambuPaymentOrder', name: 'payment_orders',
             local_fk: 'receiving_account_id', intermediate: 'MambuExternalAccount',
             import_path: 'external_account:account_holder_id',
             many_to_one_name: 'receiving_account_holder'
      end
    end
  end
end
