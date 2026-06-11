module ForestAdminDatasourceMambuPayments
  class Client
    module Reads
      def list_connected_accounts(**params)  = list_resource('connected_accounts', params)
      def count_connected_accounts(**params) = count_resource('connected_accounts', params)
      def find_connected_account(id)         = get_resource('connected_accounts', id)

      def list_payment_orders(**params)  = list_resource('payment_orders', params)
      def count_payment_orders(**params) = count_resource('payment_orders', params)
      def find_payment_order(id)         = get_resource('payment_orders', id)

      def list_transactions(**params)  = list_resource('transactions', params)
      def count_transactions(**params) = count_resource('transactions', params)
      def find_transaction(id)         = get_resource('transactions', id)

      def list_balances(**params)  = list_resource('balances', params)
      def count_balances(**params) = count_resource('balances', params)
      def find_balance(id)         = get_resource('balances', id)

      def list_account_holders(**params)  = list_resource('account_holders', params)
      def count_account_holders(**params) = count_resource('account_holders', params)
      def find_account_holder(id)         = get_resource('account_holders', id)

      def list_external_accounts(**params)  = list_resource('external_accounts', params)
      def count_external_accounts(**params) = count_resource('external_accounts', params)
      def find_external_account(id)         = get_resource('external_accounts', id)

      def list_internal_accounts(**params)  = list_resource('internal_accounts', params)
      def count_internal_accounts(**params) = count_resource('internal_accounts', params)
      def find_internal_account(id)         = get_resource('internal_accounts', id)

      def list_incoming_payments(**params)  = list_resource('incoming_payments', params)
      def count_incoming_payments(**params) = count_resource('incoming_payments', params)
      def find_incoming_payment(id)         = get_resource('incoming_payments', id)

      def list_direct_debit_mandates(**params)  = list_resource('direct_debit_mandates', params)
      def count_direct_debit_mandates(**params) = count_resource('direct_debit_mandates', params)
      def find_direct_debit_mandate(id)         = get_resource('direct_debit_mandates', id)

      def list_expected_payments(**params)  = list_resource('expected_payments', params)
      def count_expected_payments(**params) = count_resource('expected_payments', params)
      def find_expected_payment(id)         = get_resource('expected_payments', id)

      def list_events(**params)  = list_resource('events', params)
      def count_events(**params) = count_resource('events', params)
      def find_event(id)         = get_resource('events', id)

      def list_files(**params)  = list_resource('files', params)
      def count_files(**params) = count_resource('files', params)
      def find_file(id)         = get_resource('files', id)

      def list_returns(**params)  = list_resource('returns', params)
      def count_returns(**params) = count_resource('returns', params)
      def find_return(id)         = get_resource('returns', id)

      # Claims are arrived-from-the-network resources (created via the sandbox
      # simulator or by the counterparty bank). No POST/PATCH/DELETE here:
      # accept/reject are lifecycle actions and would belong in a plugin.
      def list_claims(**params)  = list_resource('claims', params)
      def count_claims(**params) = count_resource('claims', params)
      def find_claim(id)         = get_resource('claims', id)

      def list_reconciliations(**params)  = list_resource('reconciliations', params)
      def count_reconciliations(**params) = count_resource('reconciliations', params)
      def find_reconciliation(id)         = get_resource('reconciliations', id)

      # Payment captures are emitted by PSPs (or registered manually via API
      # to reconcile reporting files). create/update/cancel exist on the
      # Numeral API but are lifecycle operations deferred to a future plugin.
      def list_payment_captures(**params)  = list_resource('payment_captures', params)
      def count_payment_captures(**params) = count_resource('payment_captures', params)
      def find_payment_capture(id)         = get_resource('payment_captures', id)

      # Payee verification requests are emitted by Numeral when an outgoing
      # verification is sent (via the TriggerPayeeVerification plugin) or
      # when an incoming verification arrives from the network. send /
      # simulate are exposed as smart actions, not collection writes.
      def list_payee_verification_requests(**params)  = list_resource('payee_verification_requests', params)
      def count_payee_verification_requests(**params) = count_resource('payee_verification_requests', params)
      def find_payee_verification_request(id)         = get_resource('payee_verification_requests', id)
    end
  end
end
