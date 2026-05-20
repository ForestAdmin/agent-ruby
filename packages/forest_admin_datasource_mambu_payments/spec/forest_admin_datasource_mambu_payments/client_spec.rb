RSpec.describe ForestAdminDatasourceMambuPayments::Client do
  let(:configuration) { ForestAdminDatasourceMambuPayments::Configuration.new(api_key: 'k') }
  let(:client) { described_class.new(configuration) }
  let(:base) { "#{configuration.base_url}/v1" }

  def json(payload, status = 200)
    { status: status, body: payload.is_a?(String) ? payload : payload.to_json,
      headers: { 'Content-Type' => 'application/json' } }
  end

  describe 'authentication' do
    it 'sends the api key in the x-api-key header (no Bearer prefix)' do
      stub_request(:get, "#{base}/connected_accounts")
        .with(headers: { 'x-api-key' => 'k' })
        .to_return(json('records' => []))

      client.list_connected_accounts
      expect(WebMock).to have_requested(:get, "#{base}/connected_accounts")
        .with(headers: { 'x-api-key' => 'k' })
    end
  end

  describe '#list_connected_accounts' do
    it 'returns the array under the "records" wrapper' do
      stub_request(:get, "#{base}/connected_accounts")
        .to_return(json('records' => [{ 'id' => 'a' }, { 'id' => 'b' }]))

      expect(client.list_connected_accounts.map { |r| r['id'] }).to eq(%w[a b])
    end

    it 'also accepts a "data" wrapper' do
      stub_request(:get, "#{base}/connected_accounts")
        .to_return(json('data' => [{ 'id' => 'a' }]))

      expect(client.list_connected_accounts.size).to eq(1)
    end

    it 'accepts an array body directly' do
      stub_request(:get, "#{base}/connected_accounts")
        .to_return(json([{ 'id' => 'a' }]))

      expect(client.list_connected_accounts.size).to eq(1)
    end

    it 'falls back to the first array-valued field when the wrapper key is unknown' do
      stub_request(:get, "#{base}/connected_accounts")
        .to_return(json('accounts' => [{ 'id' => 'a' }], 'total' => 1))

      expect(client.list_connected_accounts.size).to eq(1)
    end

    it 'returns [] when the body is a Hash with no array values' do
      stub_request(:get, "#{base}/connected_accounts").to_return(json('total' => 0))
      expect(client.list_connected_accounts).to eq([])
    end

    it 'forwards query params, joining arrays with commas' do
      stub_request(:get, "#{base}/connected_accounts")
        .with(query: { 'limit' => '10', 'ids' => 'a,b' })
        .to_return(json('records' => []))

      client.list_connected_accounts(limit: 10, ids: %w[a b])
      expect(WebMock).to have_requested(:get, "#{base}/connected_accounts")
        .with(query: hash_including('limit' => '10', 'ids' => 'a,b'))
    end

    it 'drops nil params before sending' do
      stub_request(:get, "#{base}/connected_accounts")
        .with(query: { 'limit' => '5' })
        .to_return(json('records' => []))

      client.list_connected_accounts(limit: 5, cursor: nil)
      expect(WebMock).to have_requested(:get, "#{base}/connected_accounts")
        .with(query: { 'limit' => '5' })
    end

    it 'raises APIError on 5xx' do
      stub_request(:get, "#{base}/connected_accounts").to_return(status: 500, body: 'boom')
      expect { client.list_connected_accounts }
        .to raise_error(ForestAdminDatasourceMambuPayments::APIError, /list\(connected_accounts\)/)
    end
  end

  describe '#find_connected_account' do
    it 'returns the record directly when the body is not wrapped' do
      stub_request(:get, "#{base}/connected_accounts/abc")
        .to_return(json('id' => 'abc', 'name' => 'Acme'))

      expect(client.find_connected_account('abc')).to include('id' => 'abc', 'name' => 'Acme')
    end

    it 'unwraps a top-level "data" hash' do
      stub_request(:get, "#{base}/connected_accounts/abc")
        .to_return(json('data' => { 'id' => 'abc' }))

      expect(client.find_connected_account('abc')).to eq('id' => 'abc')
    end

    it 'returns nil on 404' do
      stub_request(:get, "#{base}/connected_accounts/xyz").to_return(status: 404, body: '{}')
      expect(client.find_connected_account('xyz')).to be_nil
    end

    it 'raises APIError on other failures' do
      stub_request(:get, "#{base}/connected_accounts/xyz").to_return(status: 500, body: 'boom')
      expect { client.find_connected_account('xyz') }
        .to raise_error(ForestAdminDatasourceMambuPayments::APIError, /get\(connected_accounts/)
    end
  end

  describe '#create_connected_account' do
    it 'POSTs the payload as JSON and returns the response body' do
      stub_request(:post, "#{base}/connected_accounts")
        .with(body: { 'name' => 'Acme' }.to_json,
              headers: { 'Content-Type' => 'application/json' })
        .to_return(json('id' => 'new', 'name' => 'Acme'))

      expect(client.create_connected_account('name' => 'Acme')).to include('id' => 'new')
    end
  end

  describe '#update_connected_account' do
    it 'PATCHes the payload to /resource/:id' do
      stub_request(:patch, "#{base}/connected_accounts/abc")
        .with(body: { 'name' => 'NewName' }.to_json)
        .to_return(json('id' => 'abc', 'name' => 'NewName'))

      expect(client.update_connected_account('abc', 'name' => 'NewName'))
        .to include('name' => 'NewName')
    end
  end

  describe '#delete_connected_account' do
    it 'DELETEs /resource/:id and returns true on success' do
      stub_request(:delete, "#{base}/connected_accounts/abc").to_return(status: 204, body: '')
      expect(client.delete_connected_account('abc')).to be(true)
    end
  end

  describe 'payment_orders / transactions / balances' do
    it 'list_payment_orders hits /payment_orders' do
      stub_request(:get, "#{base}/payment_orders").to_return(json('records' => []))
      client.list_payment_orders
      expect(WebMock).to have_requested(:get, "#{base}/payment_orders")
    end

    it 'find_payment_order hits /payment_orders/:id' do
      stub_request(:get, "#{base}/payment_orders/po1").to_return(json('id' => 'po1'))
      expect(client.find_payment_order('po1')).to include('id' => 'po1')
    end

    it 'list_transactions hits /transactions' do
      stub_request(:get, "#{base}/transactions").to_return(json('records' => []))
      client.list_transactions
      expect(WebMock).to have_requested(:get, "#{base}/transactions")
    end

    it 'find_transaction hits /transactions/:id' do
      stub_request(:get, "#{base}/transactions/tx1").to_return(json('id' => 'tx1'))
      expect(client.find_transaction('tx1')).to include('id' => 'tx1')
    end

    it 'list_balances hits /balances' do
      stub_request(:get, "#{base}/balances").to_return(json('records' => []))
      client.list_balances
      expect(WebMock).to have_requested(:get, "#{base}/balances")
    end

    it 'find_balance hits /balances/:id' do
      stub_request(:get, "#{base}/balances/bal1").to_return(json('id' => 'bal1'))
      expect(client.find_balance('bal1')).to include('id' => 'bal1')
    end

    it 'create_payment_order POSTs to /payment_orders' do
      stub_request(:post, "#{base}/payment_orders").to_return(json('id' => 'po1'))
      expect(client.create_payment_order({})).to include('id' => 'po1')
    end

    it 'update_payment_order PATCHes /payment_orders/:id' do
      stub_request(:patch, "#{base}/payment_orders/po1").to_return(json('id' => 'po1'))
      expect(client.update_payment_order('po1', {})).to include('id' => 'po1')
    end

    it 'delete_payment_order DELETEs /payment_orders/:id' do
      stub_request(:delete, "#{base}/payment_orders/po1").to_return(status: 204, body: '')
      expect(client.delete_payment_order('po1')).to be(true)
    end
  end

  describe 'account_holders' do
    it 'list_account_holders hits /account_holders' do
      stub_request(:get, "#{base}/account_holders").to_return(json('records' => []))
      client.list_account_holders
      expect(WebMock).to have_requested(:get, "#{base}/account_holders")
    end

    it 'find_account_holder hits /account_holders/:id' do
      stub_request(:get, "#{base}/account_holders/ah1").to_return(json('id' => 'ah1'))
      expect(client.find_account_holder('ah1')).to include('id' => 'ah1')
    end

    it 'create_account_holder POSTs to /account_holders' do
      stub_request(:post, "#{base}/account_holders").to_return(json('id' => 'ah1'))
      expect(client.create_account_holder({})).to include('id' => 'ah1')
    end

    it 'update_account_holder PATCHes /account_holders/:id' do
      stub_request(:patch, "#{base}/account_holders/ah1").to_return(json('id' => 'ah1'))
      expect(client.update_account_holder('ah1', {})).to include('id' => 'ah1')
    end

    it 'delete_account_holder DELETEs /account_holders/:id' do
      stub_request(:delete, "#{base}/account_holders/ah1").to_return(status: 204, body: '')
      expect(client.delete_account_holder('ah1')).to be(true)
    end
  end

  describe 'external_accounts' do
    it 'list_external_accounts hits /external_accounts' do
      stub_request(:get, "#{base}/external_accounts").to_return(json('records' => []))
      client.list_external_accounts
      expect(WebMock).to have_requested(:get, "#{base}/external_accounts")
    end

    it 'find_external_account hits /external_accounts/:id' do
      stub_request(:get, "#{base}/external_accounts/ea1").to_return(json('id' => 'ea1'))
      expect(client.find_external_account('ea1')).to include('id' => 'ea1')
    end

    it 'create_external_account POSTs to /external_accounts' do
      stub_request(:post, "#{base}/external_accounts").to_return(json('id' => 'ea1'))
      expect(client.create_external_account({})).to include('id' => 'ea1')
    end

    it 'update_external_account PATCHes /external_accounts/:id' do
      stub_request(:patch, "#{base}/external_accounts/ea1").to_return(json('id' => 'ea1'))
      expect(client.update_external_account('ea1', {})).to include('id' => 'ea1')
    end

    it 'delete_external_account DELETEs /external_accounts/:id' do
      stub_request(:delete, "#{base}/external_accounts/ea1").to_return(status: 204, body: '')
      expect(client.delete_external_account('ea1')).to be(true)
    end
  end

  describe 'internal_accounts' do
    it 'list_internal_accounts hits /internal_accounts' do
      stub_request(:get, "#{base}/internal_accounts").to_return(json('records' => []))
      client.list_internal_accounts
      expect(WebMock).to have_requested(:get, "#{base}/internal_accounts")
    end

    it 'find_internal_account hits /internal_accounts/:id' do
      stub_request(:get, "#{base}/internal_accounts/ia1").to_return(json('id' => 'ia1'))
      expect(client.find_internal_account('ia1')).to include('id' => 'ia1')
    end

    it 'create_internal_account POSTs to /internal_accounts' do
      stub_request(:post, "#{base}/internal_accounts").to_return(json('id' => 'ia1'))
      expect(client.create_internal_account({})).to include('id' => 'ia1')
    end

    it 'update_internal_account PATCHes /internal_accounts/:id' do
      stub_request(:patch, "#{base}/internal_accounts/ia1").to_return(json('id' => 'ia1'))
      expect(client.update_internal_account('ia1', {})).to include('id' => 'ia1')
    end

    it 'delete_internal_account DELETEs /internal_accounts/:id' do
      stub_request(:delete, "#{base}/internal_accounts/ia1").to_return(status: 204, body: '')
      expect(client.delete_internal_account('ia1')).to be(true)
    end
  end

  describe 'incoming_payments' do
    it 'list_incoming_payments hits /incoming_payments' do
      stub_request(:get, "#{base}/incoming_payments").to_return(json('records' => []))
      client.list_incoming_payments
      expect(WebMock).to have_requested(:get, "#{base}/incoming_payments")
    end

    it 'find_incoming_payment hits /incoming_payments/:id' do
      stub_request(:get, "#{base}/incoming_payments/ip1").to_return(json('id' => 'ip1'))
      expect(client.find_incoming_payment('ip1')).to include('id' => 'ip1')
    end
  end

  describe 'direct_debit_mandates' do
    it 'list_direct_debit_mandates hits /direct_debit_mandates' do
      stub_request(:get, "#{base}/direct_debit_mandates").to_return(json('records' => []))
      client.list_direct_debit_mandates
      expect(WebMock).to have_requested(:get, "#{base}/direct_debit_mandates")
    end

    it 'find_direct_debit_mandate hits /direct_debit_mandates/:id' do
      stub_request(:get, "#{base}/direct_debit_mandates/dm1").to_return(json('id' => 'dm1'))
      expect(client.find_direct_debit_mandate('dm1')).to include('id' => 'dm1')
    end

    it 'create_direct_debit_mandate POSTs to /direct_debit_mandates' do
      stub_request(:post, "#{base}/direct_debit_mandates").to_return(json('id' => 'dm1'))
      expect(client.create_direct_debit_mandate({})).to include('id' => 'dm1')
    end

    it 'update_direct_debit_mandate PATCHes /direct_debit_mandates/:id' do
      stub_request(:patch, "#{base}/direct_debit_mandates/dm1").to_return(json('id' => 'dm1'))
      expect(client.update_direct_debit_mandate('dm1', {})).to include('id' => 'dm1')
    end

    it 'delete_direct_debit_mandate DELETEs /direct_debit_mandates/:id' do
      stub_request(:delete, "#{base}/direct_debit_mandates/dm1").to_return(status: 204, body: '')
      expect(client.delete_direct_debit_mandate('dm1')).to be(true)
    end
  end

  describe 'expected_payments' do
    it 'list_expected_payments hits /expected_payments' do
      stub_request(:get, "#{base}/expected_payments").to_return(json('records' => []))
      client.list_expected_payments
      expect(WebMock).to have_requested(:get, "#{base}/expected_payments")
    end

    it 'find_expected_payment hits /expected_payments/:id' do
      stub_request(:get, "#{base}/expected_payments/ep1").to_return(json('id' => 'ep1'))
      expect(client.find_expected_payment('ep1')).to include('id' => 'ep1')
    end

    it 'create_expected_payment POSTs to /expected_payments' do
      stub_request(:post, "#{base}/expected_payments").to_return(json('id' => 'ep1'))
      expect(client.create_expected_payment({})).to include('id' => 'ep1')
    end

    it 'update_expected_payment PATCHes /expected_payments/:id' do
      stub_request(:patch, "#{base}/expected_payments/ep1").to_return(json('id' => 'ep1'))
      expect(client.update_expected_payment('ep1', {})).to include('id' => 'ep1')
    end

    it 'delete_expected_payment DELETEs /expected_payments/:id' do
      stub_request(:delete, "#{base}/expected_payments/ep1").to_return(status: 204, body: '')
      expect(client.delete_expected_payment('ep1')).to be(true)
    end
  end

  describe 'events' do
    it 'list_events hits /events' do
      stub_request(:get, "#{base}/events").to_return(json('records' => []))
      client.list_events
      expect(WebMock).to have_requested(:get, "#{base}/events")
    end

    it 'find_event hits /events/:id' do
      stub_request(:get, "#{base}/events/ev1").to_return(json('id' => 'ev1'))
      expect(client.find_event('ev1')).to include('id' => 'ev1')
    end
  end

  describe 'files' do
    it 'list_files hits /files' do
      stub_request(:get, "#{base}/files").to_return(json('records' => []))
      client.list_files
      expect(WebMock).to have_requested(:get, "#{base}/files")
    end

    it 'find_file hits /files/:id' do
      stub_request(:get, "#{base}/files/f1").to_return(json('id' => 'f1'))
      expect(client.find_file('f1')).to include('id' => 'f1')
    end
  end

  describe 'claims' do
    it 'list_claims hits /claims' do
      stub_request(:get, "#{base}/claims").to_return(json('records' => []))
      client.list_claims
      expect(WebMock).to have_requested(:get, "#{base}/claims")
    end

    it 'find_claim hits /claims/:id' do
      stub_request(:get, "#{base}/claims/clm1").to_return(json('id' => 'clm1'))
      expect(client.find_claim('clm1')).to include('id' => 'clm1')
    end
  end

  describe 'returns' do
    it 'list_returns hits /returns' do
      stub_request(:get, "#{base}/returns").to_return(json('records' => []))
      client.list_returns
      expect(WebMock).to have_requested(:get, "#{base}/returns")
    end

    it 'find_return hits /returns/:id' do
      stub_request(:get, "#{base}/returns/ret1").to_return(json('id' => 'ret1'))
      expect(client.find_return('ret1')).to include('id' => 'ret1')
    end

    it 'create_return POSTs to /returns' do
      stub_request(:post, "#{base}/returns").to_return(json('id' => 'ret1'))
      expect(client.create_return({})).to include('id' => 'ret1')
    end

    it 'update_return PATCHes /returns/:id' do
      stub_request(:patch, "#{base}/returns/ret1").to_return(json('id' => 'ret1'))
      expect(client.update_return('ret1', {})).to include('id' => 'ret1')
    end
  end

  describe 'action endpoints (approve/cancel/verify)' do
    it 'approve_payment_order POSTs to /payment_orders/:id/approve' do
      stub_request(:post, "#{base}/payment_orders/po_1/approve").to_return(json('id' => 'po_1', 'status' => 'approved'))
      expect(client.approve_payment_order('po_1')).to include('id' => 'po_1', 'status' => 'approved')
    end

    it 'cancel_payment_order POSTs to /payment_orders/:id/cancel with the reason' do
      stub_request(:post, "#{base}/payment_orders/po_1/cancel")
        .with(body: { reason: 'AC01' }.to_json)
        .to_return(json('id' => 'po_1', 'status' => 'canceled'))
      expect(client.cancel_payment_order('po_1', 'reason' => 'AC01')).to include('status' => 'canceled')
    end

    it 'verify_external_account POSTs to /external_accounts/:id/verify' do
      stub_request(:post, "#{base}/external_accounts/ea_1/verify")
        .to_return(json('id' => 'ea_1', 'status' => 'pending_verification'))
      expect(client.verify_external_account('ea_1')).to include('status' => 'pending_verification')
    end

    it 'wraps action endpoint errors with the operation name' do
      stub_request(:post, "#{base}/payment_orders/bad/approve").to_return(status: 422, body: '{}')
      expect { client.approve_payment_order('bad') }
        .to raise_error(ForestAdminDatasourceMambuPayments::APIError, %r{approve\(payment_orders/bad\)})
    end
  end
end
