RSpec.describe ForestAdminDatasourceMambuPayments::Plugins::Relations::LinkIncomingPaymentToReturns do
  let(:datasource_customizer) { ForestAdminDatasourceMambuPayments::PluginSupport::FakeDatasourceCustomizer.new }

  def install
    described_class.new.run(datasource_customizer, nil, {})
    datasource_customizer.collections
  end

  describe '#run' do
    it 'adds OneToMany returns on MambuIncomingPayment via related_payment_id' do
      install
      rel = datasource_customizer.collections['MambuIncomingPayment'].one_to_many_relations['returns']
      expect(rel).to include(
        foreign_collection: 'MambuReturn',
        origin_key: 'related_payment_id',
        origin_key_target: 'id'
      )
    end

    it 'does not customize MambuReturn (FK + API filter already native)' do
      install
      expect(datasource_customizer.collections.keys).to contain_exactly('MambuIncomingPayment')
    end

    it 'raises ArgumentError when installed without a datasource_customizer (collection-level use)' do
      expect { described_class.new.run(nil, nil, {}) }
        .to raise_error(ArgumentError, /datasource level/)
    end
  end
end
