RSpec.describe ForestAdminDatasourceMambuPayments::Plugins::Relations::LinkIncomingPaymentToExpectedPayments do
  let(:datasource_customizer) { ForestAdminDatasourceMambuPayments::PluginSupport::FakeDatasourceCustomizer.new }

  def install(opts = {})
    described_class.new.run(datasource_customizer, nil, opts)
    datasource_customizer.collections
  end

  describe '#run' do
    it 'declares a computed incoming_payment_id column on MambuExpectedPayment' do
      install
      field = datasource_customizer.collections['MambuExpectedPayment'].computed_fields['incoming_payment_id']
      expect(field).not_to be_nil
      expect(field.column_type).to eq('String')
      expect(field.dependencies).to eq(['id'])
      expect(field.get_values([{ 'id' => 'ep-1' }], nil)).to eq([nil])
    end

    it 'adds the reciprocal OneToMany matched_expected_payments on MambuIncomingPayment' do
      install
      rel = datasource_customizer.collections['MambuIncomingPayment'].one_to_many_relations['matched_expected_payments']
      expect(rel).to include(
        foreign_collection: 'MambuExpectedPayment',
        origin_key: 'incoming_payment_id',
        origin_key_target: 'id'
      )
    end

    it 'declares the virtual column before installing the operator rewrites' do
      ep = datasource_customizer.collections['MambuExpectedPayment']
      call_order = []
      allow(ep).to receive(:add_field).and_wrap_original do |orig, *args, **kw|
        call_order << :add_field
        orig.call(*args, **kw)
      end
      allow(ep).to receive(:replace_field_operator).and_wrap_original do |orig, *args, **kw|
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

  describe 'cross-reconciliation filter rewrite on incoming_payment_id' do
    let(:ep) { install['MambuExpectedPayment'] }

    it 'registers an EQUAL and IN handler on incoming_payment_id' do
      expect(ep.operator_handlers.keys).to include(
        %w[incoming_payment_id equal], %w[incoming_payment_id in]
      )
    end

    # Records used for both passes; the helper extracts transaction_id from
    # the first pass and payment_id from the second. The fake collection
    # ignores filters, so a single record set with both fields populated
    # works to verify the rewrite shape end-to-end.
    it 'rewrites EQUAL ip_id to id IN (resolved expected_payment ids)' do
      handler = ep.operator_handlers[%w[incoming_payment_id equal]]
      ctx = ForestAdminDatasourceMambuPayments::PluginSupport::FakeOperatorContext.new(
        'MambuReconciliation' => [
          { 'transaction_id' => 'tx-1', 'payment_id' => 'ep-1' },
          { 'transaction_id' => 'tx-2', 'payment_id' => 'ep-2' }
        ]
      )

      result = handler.call('ip-1', ctx)

      expect(result.field).to eq('id')
      expect(result.operator).to eq('in')
      expect(result.value).to contain_exactly('ep-1', 'ep-2')
    end

    it 'returns the no-match sentinel when the first reconciliation pass yields no transactions' do
      handler = ep.operator_handlers[%w[incoming_payment_id equal]]
      ctx = ForestAdminDatasourceMambuPayments::PluginSupport::FakeOperatorContext.new(
        'MambuReconciliation' => []
      )

      result = handler.call('ip-unmatched', ctx)

      expect(result.field).to eq('id')
      expect(result.value).to eq('00000000-0000-0000-0000-000000000000')
    end

    it 'returns the no-match sentinel when the filter value is blank' do
      handler = ep.operator_handlers[%w[incoming_payment_id in]]
      ctx = ForestAdminDatasourceMambuPayments::PluginSupport::FakeOperatorContext.new({})

      result = handler.call([nil, ''], ctx)

      expect(result.value).to eq('00000000-0000-0000-0000-000000000000')
    end
  end
end
