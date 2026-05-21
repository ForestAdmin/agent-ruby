module ForestAdminDatasourceMambuPayments
  class Client
    module Writes
      def create_payment_order(attrs)     = post_resource('payment_orders', attrs)
      def update_payment_order(id, attrs) = patch_resource('payment_orders', id, attrs)
      def delete_payment_order(id)        = delete_resource('payment_orders', id)
      def approve_payment_order(id, attrs = {}) = post_action_resource('payment_orders', id, 'approve', attrs)
      def cancel_payment_order(id, attrs = {})  = post_action_resource('payment_orders', id, 'cancel', attrs)

      def create_account_holder(attrs)     = post_resource('account_holders', attrs)
      def update_account_holder(id, attrs) = patch_resource('account_holders', id, attrs)
      def delete_account_holder(id)        = delete_resource('account_holders', id)

      def create_external_account(attrs)     = post_resource('external_accounts', attrs)
      def update_external_account(id, attrs) = patch_resource('external_accounts', id, attrs)
      def delete_external_account(id)        = delete_resource('external_accounts', id)
      def verify_external_account(id, attrs = {}) = post_action_resource('external_accounts', id, 'verify', attrs)

      def create_internal_account(attrs)     = post_resource('internal_accounts', attrs)
      def update_internal_account(id, attrs) = patch_resource('internal_accounts', id, attrs)
      def delete_internal_account(id)        = delete_resource('internal_accounts', id)

      def create_direct_debit_mandate(attrs)     = post_resource('direct_debit_mandates', attrs)
      def update_direct_debit_mandate(id, attrs) = patch_resource('direct_debit_mandates', id, attrs)
      def delete_direct_debit_mandate(id)        = delete_resource('direct_debit_mandates', id)

      def create_expected_payment(attrs)     = post_resource('expected_payments', attrs)
      def update_expected_payment(id, attrs) = patch_resource('expected_payments', id, attrs)
      def delete_expected_payment(id)        = delete_resource('expected_payments', id)

      # Numeral has no DELETE on /returns; the lifecycle "cancel"/"approve" are
      # exposed as side-effect actions and would belong in a plugin, not here.
      def create_return(attrs)     = post_resource('returns', attrs)
      def update_return(id, attrs) = patch_resource('returns', id, attrs)

      # Numeral has no DELETE on /reconciliations either; cancel is a lifecycle
      # action and is deferred to a future plugin.
      def create_reconciliation(attrs)     = post_resource('reconciliations', attrs)
      def update_reconciliation(id, attrs) = patch_resource('reconciliations', id, attrs)
    end
  end
end
