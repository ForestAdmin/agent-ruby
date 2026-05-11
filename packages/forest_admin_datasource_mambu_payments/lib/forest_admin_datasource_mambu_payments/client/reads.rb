module ForestAdminDatasourceMambuPayments
  class Client
    module Reads
      def list_connected_accounts(**params) = list_resource('connected_accounts', params)
      def find_connected_account(id)        = get_resource('connected_accounts', id)

      def list_payment_orders(**params) = list_resource('payment_orders', params)
      def find_payment_order(id)        = get_resource('payment_orders', id)

      def list_transactions(**params) = list_resource('transactions', params)
      def find_transaction(id)        = get_resource('transactions', id)

      def list_balances(**params) = list_resource('balances', params)
      def find_balance(id)        = get_resource('balances', id)

      def list_account_holders(**params) = list_resource('account_holders', params)
      def find_account_holder(id)        = get_resource('account_holders', id)

      def list_external_accounts(**params) = list_resource('external_accounts', params)
      def find_external_account(id)        = get_resource('external_accounts', id)

      def list_internal_accounts(**params) = list_resource('internal_accounts', params)
      def find_internal_account(id)        = get_resource('internal_accounts', id)
    end
  end
end
