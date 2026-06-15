RSpec.describe ForestAdminDatasourceMambuPayments::Plugins::Relations::LinkAccountHolderToDirectDebitMandates do
  let(:datasource_customizer) { ForestAdminDatasourceMambuPayments::PluginSupport::FakeDatasourceCustomizer.new }

  def install(opts = {})
    described_class.new.run(datasource_customizer, nil, opts)
    datasource_customizer.collections
  end

  describe '#run' do
    it 'imports external_account:account_holder_id onto MambuDirectDebitMandate' do
      install
      imports = datasource_customizer.collections['MambuDirectDebitMandate'].imported_fields
      expect(imports).to have_key('account_holder_id')
      expect(imports['account_holder_id']).to include(path: 'external_account:account_holder_id', readonly: true)
    end

    it 'adds a ManyToOne account_holder relation on MambuDirectDebitMandate' do
      install
      rel = datasource_customizer.collections['MambuDirectDebitMandate'].many_to_one_relations['account_holder']
      expect(rel).to include(
        foreign_collection: 'MambuAccountHolder',
        foreign_key: 'account_holder_id',
        foreign_key_target: 'id'
      )
    end

    it 'adds the reciprocal OneToMany direct_debit_mandates on MambuAccountHolder' do
      install
      rel = datasource_customizer.collections['MambuAccountHolder'].one_to_many_relations['direct_debit_mandates']
      expect(rel).to include(
        foreign_collection: 'MambuDirectDebitMandate',
        origin_key: 'account_holder_id',
        origin_key_target: 'id'
      )
    end

    it 'imports the field before declaring the ManyToOne (the relation depends on the imported column)' do
      ddm = datasource_customizer.collections['MambuDirectDebitMandate']
      call_order = []
      allow(ddm).to receive(:import_field).and_wrap_original do |orig, *args, **kw|
        call_order << :import
        orig.call(*args, **kw)
      end
      allow(ddm).to receive(:add_many_to_one_relation).and_wrap_original do |orig, *args, **kw|
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
    let(:ddm) { install['MambuDirectDebitMandate'] }

    it 'registers an EQUAL and IN handler on account_holder_id' do
      expect(ddm.operator_handlers.keys).to include(
        %w[account_holder_id equal], %w[account_holder_id in]
      )
    end

    it 'rewrites EQUAL holder_id to external_account_id IN (resolved ids)' do
      handler = ddm.operator_handlers[%w[account_holder_id equal]]
      ctx = ForestAdminDatasourceMambuPayments::PluginSupport::FakeOperatorContext.new(
        'MambuExternalAccount' => [{ 'id' => 'ea1' }, { 'id' => 'ea2' }]
      )

      result = handler.call('holder-1', ctx)

      expect(result.field).to eq('external_account_id')
      expect(result.operator).to eq('in')
      expect(result.value).to contain_exactly('ea1', 'ea2')
    end

    it 'returns a no-match sentinel leaf when the holder has no external accounts' do
      handler = ddm.operator_handlers[%w[account_holder_id equal]]
      ctx = ForestAdminDatasourceMambuPayments::PluginSupport::FakeOperatorContext.new(
        'MambuExternalAccount' => []
      )

      result = handler.call('holder-without-accounts', ctx)

      expect(result.field).to eq('external_account_id')
      expect(result.operator).to eq('equal')
      expect(result.value).to eq('00000000-0000-0000-0000-000000000000')
    end
  end
end
