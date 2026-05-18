RSpec.describe ForestAdminDatasourceMambuPayments::Plugins::TriggerPayeeVerification do
  let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
  let(:datasource) { instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client) }
  let(:result_builder) { ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder.new }
  let(:collection_customizer) { ForestAdminDatasourceMambuPayments::PluginSupport::FakeCollection.new }
  let(:record_id_field) { 'mambu_external_account_id' }
  let(:action_scope) { ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope }

  def register(opts = {})
    described_class.new.run(nil, collection_customizer,
                            { datasource: datasource, record_id_field: record_id_field }.merge(opts))
    collection_customizer.registered
  end

  describe '#run' do
    it 'registers both single and bulk by default' do
      register
      expect(collection_customizer.registered.keys).to contain_exactly(
        'Trigger payee verification', 'Trigger payee verification on selected accounts'
      )
    end

    it 'honors :scopes to filter variants' do
      register(scopes: %i[bulk])
      expect(collection_customizer.registered.keys).to contain_exactly(
        'Trigger payee verification on selected accounts'
      )
    end

    it 'binds the right ActionScope to each variant' do
      register
      single = collection_customizer.registered['Trigger payee verification']
      bulk   = collection_customizer.registered['Trigger payee verification on selected accounts']
      expect(single.scope).to eq(action_scope::SINGLE)
      expect(bulk.scope).to eq(action_scope::BULK)
    end

    it 'raises ArgumentError without :record_id_field' do
      expect { described_class.new.run(nil, collection_customizer, datasource: datasource) }
        .to raise_error(ArgumentError, /record_id_field/)
    end
  end

  describe 'executor' do
    let(:single) { register[collection_customizer.registered.keys.first] }
    let(:bulk)   { register[collection_customizer.registered.keys.last] }

    it 'POSTs /external_accounts/{id}/verify for each id' do
      allow(client).to receive(:verify_external_account)
      context = ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(
        records: %w[a b].map { |id| { record_id_field => id } }
      )

      result = bulk.execute.call(context, result_builder)

      %w[a b].each { |id| expect(client).to have_received(:verify_external_account).with(id) }
      expect(result[:type]).to eq('Success')
      expect(result[:message]).to include('2 external accounts now pending verification')
    end

    it 'returns an Error when no id is found on the host record' do
      allow(client).to receive(:verify_external_account)
      context = ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(
        records: [{ record_id_field => nil }]
      )

      result = single.execute.call(context, result_builder)

      expect(result[:type]).to eq('Error')
      expect(result[:message]).to include(record_id_field)
    end

    it 'surfaces partial success on bulk: continues past per-id failures' do
      allow(client).to receive(:verify_external_account).with('a')
      allow(client).to receive(:verify_external_account).with('b').and_raise(StandardError, 'boom')
      allow(ForestAdminDatasourceMambuPayments.logger).to receive(:warn)
      context = ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(
        records: %w[a b].map { |id| { record_id_field => id } }
      )

      result = bulk.execute.call(context, result_builder)

      expect(result[:type]).to eq('Success')
      expect(result[:message]).to include('External account #a', 'now pending verification', '1 failed: b')
    end
  end
end
