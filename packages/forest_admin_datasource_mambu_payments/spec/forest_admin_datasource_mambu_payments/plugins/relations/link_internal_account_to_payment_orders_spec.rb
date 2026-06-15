RSpec.describe ForestAdminDatasourceMambuPayments::Plugins::Relations::LinkInternalAccountToPaymentOrders do
  let(:datasource_customizer) { ForestAdminDatasourceMambuPayments::PluginSupport::FakeDatasourceCustomizer.new }

  def install(opts = {})
    described_class.new.run(datasource_customizer, nil, opts)
    datasource_customizer.collections
  end

  describe '#run' do
    it 'declares a computed internal_account_id column on MambuPaymentOrder' do
      install
      field = datasource_customizer.collections['MambuPaymentOrder'].computed_fields['internal_account_id']
      expect(field).not_to be_nil
      expect(field.column_type).to eq('String')
      expect(field.dependencies).to eq(['id'])
      expect(field.get_values([{ 'id' => 'po-1' }, { 'id' => 'po-2' }], nil)).to eq([nil, nil])
    end

    it 'adds the reciprocal OneToMany payment_orders on MambuInternalAccount' do
      install
      rel = datasource_customizer.collections['MambuInternalAccount'].one_to_many_relations['payment_orders']
      expect(rel).to include(
        foreign_collection: 'MambuPaymentOrder',
        origin_key: 'internal_account_id',
        origin_key_target: 'id'
      )
    end

    it 'declares the virtual column before installing the operator rewrites' do
      po = datasource_customizer.collections['MambuPaymentOrder']
      call_order = []
      allow(po).to receive(:add_field).and_wrap_original do |orig, *args, **kw|
        call_order << :add_field
        orig.call(*args, **kw)
      end
      allow(po).to receive(:replace_field_operator).and_wrap_original do |orig, *args, **kw|
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

  describe 'two-step filter rewrite on internal_account_id' do
    let(:po) { install['MambuPaymentOrder'] }

    it 'registers an EQUAL and IN handler on internal_account_id' do
      expect(po.operator_handlers.keys).to include(
        %w[internal_account_id equal], %w[internal_account_id in]
      )
    end

    it 'rewrites EQUAL holder_id to connected_account_id IN (resolved ca ids)' do
      handler = po.operator_handlers[%w[internal_account_id equal]]
      ctx = ForestAdminDatasourceMambuPayments::PluginSupport::FakeOperatorContext.new(
        'MambuInternalAccount' => [{ 'connected_account_ids' => %w[ca-1 ca-2] }]
      )

      result = handler.call('ia-1', ctx)

      expect(result.field).to eq('connected_account_id')
      expect(result.operator).to eq('in')
      expect(result.value).to contain_exactly('ca-1', 'ca-2')
    end

    it 'rewrites IN holder_ids to connected_account_id IN (flattened, deduped ca ids)' do
      handler = po.operator_handlers[%w[internal_account_id in]]
      ctx = ForestAdminDatasourceMambuPayments::PluginSupport::FakeOperatorContext.new(
        'MambuInternalAccount' => [
          { 'connected_account_ids' => %w[ca-1 ca-2] },
          { 'connected_account_ids' => %w[ca-2 ca-3] }
        ]
      )

      result = handler.call(%w[ia-1 ia-2], ctx)

      expect(result.field).to eq('connected_account_id')
      expect(result.value).to contain_exactly('ca-1', 'ca-2', 'ca-3')
    end

    it 'returns a no-match sentinel leaf when no internal account has connected accounts' do
      handler = po.operator_handlers[%w[internal_account_id equal]]
      ctx = ForestAdminDatasourceMambuPayments::PluginSupport::FakeOperatorContext.new(
        'MambuInternalAccount' => [{ 'connected_account_ids' => [] }]
      )

      result = handler.call('ia-empty', ctx)

      expect(result.field).to eq('connected_account_id')
      expect(result.operator).to eq('equal')
      expect(result.value).to eq('00000000-0000-0000-0000-000000000000')
    end

    it 'returns a no-match sentinel leaf when the filter value is blank' do
      handler = po.operator_handlers[%w[internal_account_id in]]
      ctx = ForestAdminDatasourceMambuPayments::PluginSupport::FakeOperatorContext.new({})

      result = handler.call([nil, ''], ctx)

      expect(result.value).to eq('00000000-0000-0000-0000-000000000000')
    end
  end
end
