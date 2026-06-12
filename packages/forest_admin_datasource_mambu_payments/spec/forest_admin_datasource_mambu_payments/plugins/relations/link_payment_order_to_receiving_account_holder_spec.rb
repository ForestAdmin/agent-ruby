RSpec.describe ForestAdminDatasourceMambuPayments::Plugins::Relations::LinkPaymentOrderToReceivingAccountHolder do
  let(:datasource_customizer) { ForestAdminDatasourceMambuPayments::PluginSupport::FakeDatasourceCustomizer.new }

  def install(opts = {})
    described_class.new.run(datasource_customizer, nil, opts)
    datasource_customizer.collections
  end

  describe '#run' do
    it 'imports external_account:account_holder_id onto MambuPaymentOrder' do
      install
      imports = datasource_customizer.collections['MambuPaymentOrder'].imported_fields
      expect(imports).to have_key('account_holder_id')
      expect(imports['account_holder_id']).to include(path: 'external_account:account_holder_id', readonly: true)
    end

    it 'adds a ManyToOne receiving_account_holder relation on MambuPaymentOrder' do
      install
      rel = datasource_customizer.collections['MambuPaymentOrder'].many_to_one_relations['receiving_account_holder']
      expect(rel).to include(
        foreign_collection: 'MambuAccountHolder',
        foreign_key: 'account_holder_id',
        foreign_key_target: 'id'
      )
    end

    it 'adds the reciprocal OneToMany payment_orders on MambuAccountHolder' do
      install
      rel = datasource_customizer.collections['MambuAccountHolder'].one_to_many_relations['payment_orders']
      expect(rel).to include(
        foreign_collection: 'MambuPaymentOrder',
        origin_key: 'account_holder_id',
        origin_key_target: 'id'
      )
    end

    it 'imports the field before declaring the ManyToOne (the relation depends on the imported column)' do
      po = datasource_customizer.collections['MambuPaymentOrder']
      call_order = []
      allow(po).to receive(:import_field).and_wrap_original do |orig, *args, **kw|
        call_order << :import
        orig.call(*args, **kw)
      end
      allow(po).to receive(:add_many_to_one_relation).and_wrap_original do |orig, *args, **kw|
        call_order << :many_to_one
        orig.call(*args, **kw)
      end

      described_class.new.run(datasource_customizer, nil, {})

      expect(call_order).to eq(%i[import many_to_one])
    end

    it 'raises ArgumentError when installed without a datasource_customizer (collection-level use)' do
      expect { described_class.new.run(nil, nil, {}) }
        .to raise_error(ArgumentError, /datasource level/)
    end
  end

  describe 'two-step filter rewrite on account_holder_id' do
    let(:po) { install['MambuPaymentOrder'] }

    it 'registers an EQUAL and IN handler on account_holder_id' do
      expect(po.operator_handlers.keys).to include(
        %w[account_holder_id equal], %w[account_holder_id in]
      )
    end

    it 'rewrites EQUAL holder_id to receiving_account_id IN (resolved ids)' do
      handler = po.operator_handlers[%w[account_holder_id equal]]
      ctx = ForestAdminDatasourceMambuPayments::PluginSupport::FakeOperatorContext.new(
        'MambuExternalAccount' => [{ 'id' => 'ea-1' }, { 'id' => 'ea-2' }]
      )

      result = handler.call('holder-1', ctx)

      expect(result.field).to eq('receiving_account_id')
      expect(result.operator).to eq('in')
      expect(result.value).to contain_exactly('ea-1', 'ea-2')
    end

    it 'returns a no-match sentinel leaf when the holder has no external accounts' do
      handler = po.operator_handlers[%w[account_holder_id equal]]
      ctx = ForestAdminDatasourceMambuPayments::PluginSupport::FakeOperatorContext.new(
        'MambuExternalAccount' => []
      )

      result = handler.call('orphan-holder', ctx)

      expect(result.field).to eq('receiving_account_id')
      expect(result.value).to eq('00000000-0000-0000-0000-000000000000')
    end
  end
end
