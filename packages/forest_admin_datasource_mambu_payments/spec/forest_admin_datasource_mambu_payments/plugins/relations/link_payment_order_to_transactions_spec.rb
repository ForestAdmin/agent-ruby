RSpec.describe ForestAdminDatasourceMambuPayments::Plugins::Relations::LinkPaymentOrderToTransactions do
  let(:datasource_customizer) { ForestAdminDatasourceMambuPayments::PluginSupport::FakeDatasourceCustomizer.new }

  def install(opts = {})
    described_class.new.run(datasource_customizer, nil, opts)
    datasource_customizer.collections
  end

  describe '#run' do
    it 'declares a computed payment_order_id column on MambuTransaction' do
      install
      field = datasource_customizer.collections['MambuTransaction'].computed_fields['payment_order_id']
      expect(field).not_to be_nil
      expect(field.column_type).to eq('String')
      expect(field.dependencies).to eq(['id'])
      expect(field.get_values([{ 'id' => 'tx-1' }, { 'id' => 'tx-2' }], nil)).to eq([nil, nil])
    end

    it 'adds the reciprocal OneToMany transactions on MambuPaymentOrder' do
      install
      rel = datasource_customizer.collections['MambuPaymentOrder'].one_to_many_relations['transactions']
      expect(rel).to include(
        foreign_collection: 'MambuTransaction',
        origin_key: 'payment_order_id',
        origin_key_target: 'id'
      )
    end

    it 'declares the virtual column before installing the operator rewrites' do
      tx = datasource_customizer.collections['MambuTransaction']
      call_order = []
      allow(tx).to receive(:add_field).and_wrap_original do |orig, *args, **kw|
        call_order << :add_field
        orig.call(*args, **kw)
      end
      allow(tx).to receive(:replace_field_operator).and_wrap_original do |orig, *args, **kw|
        call_order << :replace_op
        orig.call(*args, **kw)
      end

      described_class.new.run(datasource_customizer, nil, {})

      expect(call_order.first).to eq(:add_field)
      expect(call_order).to include(:replace_op)
    end

    it 'raises ArgumentError when installed without a datasource_customizer (collection-level use)' do
      expect { described_class.new.run(nil, nil, {}) }
        .to raise_error(ArgumentError, /datasource level/)
    end
  end

  describe 'two-step filter rewrite on payment_order_id' do
    let(:tx) { install['MambuTransaction'] }

    it 'registers an EQUAL and IN handler on payment_order_id' do
      expect(tx.operator_handlers.keys).to include(
        %w[payment_order_id equal], %w[payment_order_id in]
      )
    end

    it 'rewrites EQUAL po_id to id IN (resolved transaction ids)' do
      handler = tx.operator_handlers[%w[payment_order_id equal]]
      ctx = ForestAdminDatasourceMambuPayments::PluginSupport::FakeOperatorContext.new(
        'MambuReconciliation' => [
          { 'transaction_id' => 'tx-1' },
          { 'transaction_id' => 'tx-2' }
        ]
      )

      result = handler.call('po-1', ctx)

      expect(result.field).to eq('id')
      expect(result.operator).to eq('in')
      expect(result.value).to contain_exactly('tx-1', 'tx-2')
    end

    it 'rewrites IN po_ids to id IN (deduped transaction ids)' do
      handler = tx.operator_handlers[%w[payment_order_id in]]
      ctx = ForestAdminDatasourceMambuPayments::PluginSupport::FakeOperatorContext.new(
        'MambuReconciliation' => [
          { 'transaction_id' => 'tx-1' },
          { 'transaction_id' => 'tx-2' },
          { 'transaction_id' => 'tx-1' }
        ]
      )

      result = handler.call(%w[po-1 po-2], ctx)

      expect(result.field).to eq('id')
      expect(result.value).to contain_exactly('tx-1', 'tx-2')
    end

    it 'returns a no-match sentinel leaf when no reconciliation matches' do
      handler = tx.operator_handlers[%w[payment_order_id equal]]
      ctx = ForestAdminDatasourceMambuPayments::PluginSupport::FakeOperatorContext.new(
        'MambuReconciliation' => []
      )

      result = handler.call('po-unmatched', ctx)

      expect(result.field).to eq('id')
      expect(result.value).to eq('00000000-0000-0000-0000-000000000000')
    end

    it 'returns a no-match sentinel leaf when the filter value is blank' do
      handler = tx.operator_handlers[%w[payment_order_id in]]
      ctx = ForestAdminDatasourceMambuPayments::PluginSupport::FakeOperatorContext.new({})

      result = handler.call([nil, ''], ctx)

      expect(result.value).to eq('00000000-0000-0000-0000-000000000000')
    end
  end
end
