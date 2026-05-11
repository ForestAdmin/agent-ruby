module ForestAdminDatasourceMambuPayments
  class Client
    module Writes
      def create_connected_account(attrs)     = post_resource('connected_accounts', attrs)
      def update_connected_account(id, attrs) = patch_resource('connected_accounts', id, attrs)
      def delete_connected_account(id)        = delete_resource('connected_accounts', id)

      def create_payment_order(attrs)     = post_resource('payment_orders', attrs)
      def update_payment_order(id, attrs) = patch_resource('payment_orders', id, attrs)
      def delete_payment_order(id)        = delete_resource('payment_orders', id)

      def create_account_holder(attrs)     = post_resource('account_holders', attrs)
      def update_account_holder(id, attrs) = patch_resource('account_holders', id, attrs)
      def delete_account_holder(id)        = delete_resource('account_holders', id)

      def create_external_account(attrs)     = post_resource('external_accounts', attrs)
      def update_external_account(id, attrs) = patch_resource('external_accounts', id, attrs)
      def delete_external_account(id)        = delete_resource('external_accounts', id)

      def create_internal_account(attrs)     = post_resource('internal_accounts', attrs)
      def update_internal_account(id, attrs) = patch_resource('internal_accounts', id, attrs)
      def delete_internal_account(id)        = delete_resource('internal_accounts', id)
    end
  end
end
