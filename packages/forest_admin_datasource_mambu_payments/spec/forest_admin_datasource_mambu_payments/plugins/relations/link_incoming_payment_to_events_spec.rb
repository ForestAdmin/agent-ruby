RSpec.describe ForestAdminDatasourceMambuPayments::Plugins::Relations::LinkIncomingPaymentToEvents do
  let(:datasource_customizer) { ForestAdminDatasourceMambuPayments::PluginSupport::FakeDatasourceCustomizer.new }

  def install
    described_class.new.run(datasource_customizer, nil, {})
    datasource_customizer.collections
  end

  describe '#run' do
    it 'adds OneToMany events on MambuIncomingPayment via related_object_id' do
      install
      rel = datasource_customizer.collections['MambuIncomingPayment'].one_to_many_relations['events']
      expect(rel).to include(
        foreign_collection: 'MambuEvent',
        origin_key: 'related_object_id',
        origin_key_target: 'id'
      )
    end

    it 'does not customize MambuEvent (api_filters live in the collection itself)' do
      install
      expect(datasource_customizer.collections.keys).to contain_exactly('MambuIncomingPayment')
    end

    it 'raises ArgumentError when installed without a datasource_customizer (collection-level use)' do
      expect { described_class.new.run(nil, nil, {}) }
        .to raise_error(ArgumentError, /datasource level/)
    end
  end
end
