RSpec.describe ForestAdminDatasourceMambuPayments::Plugins::Relations::LinkInternalAccountToBalances do
  let(:datasource_customizer) { ForestAdminDatasourceMambuPayments::PluginSupport::FakeDatasourceCustomizer.new }

  def install(opts = {})
    described_class.new.run(datasource_customizer, nil, opts)
    datasource_customizer.collections
  end

  describe '#run' do
    it 'declares a computed internal_account_id column on MambuBalance' do
      install
      field = datasource_customizer.collections['MambuBalance'].computed_fields['internal_account_id']
      expect(field).not_to be_nil
      expect(field.column_type).to eq('String')
      expect(field.dependencies).to eq(['id'])
      expect(field.get_values([{ 'id' => 'b-1' }], nil)).to eq([nil])
    end

    it 'adds the reciprocal OneToMany balances on MambuInternalAccount' do
      install
      rel = datasource_customizer.collections['MambuInternalAccount'].one_to_many_relations['balances']
      expect(rel).to include(
        foreign_collection: 'MambuBalance',
        origin_key: 'internal_account_id',
        origin_key_target: 'id'
      )
    end

    it 'raises ArgumentError when installed without a datasource_customizer (collection-level use)' do
      expect { described_class.new.run(nil, nil, {}) }
        .to raise_error(ArgumentError, /datasource level/)
    end
  end

  describe 'two-step filter rewrite on internal_account_id' do
    let(:bal) { install['MambuBalance'] }

    it 'registers an EQUAL and IN handler on internal_account_id' do
      expect(bal.operator_handlers.keys).to include(
        %w[internal_account_id equal], %w[internal_account_id in]
      )
    end

    it 'rewrites EQUAL holder_id to connected_account_id IN (resolved ca ids)' do
      handler = bal.operator_handlers[%w[internal_account_id equal]]
      ctx = ForestAdminDatasourceMambuPayments::PluginSupport::FakeOperatorContext.new(
        'MambuInternalAccount' => [{ 'connected_account_ids' => %w[ca-1 ca-2] }]
      )

      result = handler.call('ia-1', ctx)

      expect(result.field).to eq('connected_account_id')
      expect(result.operator).to eq('in')
      expect(result.value).to contain_exactly('ca-1', 'ca-2')
    end

    it 'returns a no-match sentinel leaf when no internal account has connected accounts' do
      handler = bal.operator_handlers[%w[internal_account_id equal]]
      ctx = ForestAdminDatasourceMambuPayments::PluginSupport::FakeOperatorContext.new(
        'MambuInternalAccount' => []
      )

      result = handler.call('ia-unknown', ctx)

      expect(result.field).to eq('connected_account_id')
      expect(result.value).to eq('00000000-0000-0000-0000-000000000000')
    end
  end
end
