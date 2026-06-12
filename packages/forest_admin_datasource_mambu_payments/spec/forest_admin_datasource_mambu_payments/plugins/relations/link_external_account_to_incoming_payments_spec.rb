RSpec.describe ForestAdminDatasourceMambuPayments::Plugins::Relations::LinkExternalAccountToIncomingPayments do
  let(:datasource_customizer) { ForestAdminDatasourceMambuPayments::PluginSupport::FakeDatasourceCustomizer.new }

  def install
    described_class.new.run(datasource_customizer, nil, {})
    datasource_customizer.collections
  end

  describe '#run' do
    it 'adds OneToMany incoming_payments on MambuExternalAccount via external_account_id' do
      install
      rel = datasource_customizer.collections['MambuExternalAccount'].one_to_many_relations['incoming_payments']
      expect(rel).to include(
        foreign_collection: 'MambuIncomingPayment',
        origin_key: 'external_account_id',
        origin_key_target: 'id'
      )
    end

    it 'does not customize MambuIncomingPayment (FK already native)' do
      install
      expect(datasource_customizer.collections.keys).to contain_exactly('MambuExternalAccount')
    end

    it 'raises ArgumentError when installed without a datasource_customizer (collection-level use)' do
      expect { described_class.new.run(nil, nil, {}) }
        .to raise_error(ArgumentError, /datasource level/)
    end
  end
end
