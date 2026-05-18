RSpec.describe ForestAdminDatasourceMambuPayments::Plugins::UpdateAccountHolder do
  let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
  let(:datasource) { instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client) }
  let(:result_builder) { ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder.new }
  let(:collection_customizer) { ForestAdminDatasourceMambuPayments::PluginSupport::FakeCollection.new }
  let(:record_id_field) { 'mambu_account_holder_id' }

  def register(opts = {})
    described_class.new.run(nil, collection_customizer,
                            { datasource: datasource, record_id_field: record_id_field }.merge(opts))
    collection_customizer.registered[opts[:action_name] || described_class::NAME]
  end

  describe '#run' do
    it 'registers a SINGLE-scoped action with the documented form fields' do
      action = register

      expect(collection_customizer.registered.keys).to contain_exactly(described_class::NAME)
      expect(action.scope).to eq(ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope::SINGLE)
      expect(action.form.map { |f| f[:label] }).to eq(['Name'])
      expect(action.form.first[:is_required]).to be_falsey
    end

    it 'raises ArgumentError without :datasource' do
      expect { described_class.new.run(nil, collection_customizer, record_id_field: 'x') }
        .to raise_error(ArgumentError, /datasource/)
    end

    it 'raises ArgumentError without :record_id_field' do
      expect { described_class.new.run(nil, collection_customizer, datasource: datasource) }
        .to raise_error(ArgumentError, /record_id_field/)
    end
  end

  describe 'executor' do
    it 'PATCHes /account_holders/{id} with the changed Name' do
      action = register
      allow(client).to receive(:update_account_holder)
      context = ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(
        records: [{ record_id_field => 'ah_1' }], form_values: { 'Name' => 'New name' }
      )

      result = action.execute.call(context, result_builder)

      expect(client).to have_received(:update_account_holder).with('ah_1', 'name' => 'New name')
      expect(result[:type]).to eq('Success')
      expect(result[:message]).to include('Account holder #ah_1 updated')
    end

    it 'returns an error when no host record carries an id' do
      action = register
      allow(client).to receive(:update_account_holder)
      context = ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(
        records: [{ record_id_field => nil }], form_values: { 'Name' => 'x' }
      )

      result = action.execute.call(context, result_builder)

      expect(client).not_to have_received(:update_account_holder)
      expect(result[:type]).to eq('Error')
      expect(result[:message]).to include(record_id_field)
    end

    it 'returns an error when no field is filled in the form' do
      action = register
      allow(client).to receive(:update_account_holder)
      context = ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(
        records: [{ record_id_field => 'ah_1' }], form_values: { 'Name' => '' }
      )

      result = action.execute.call(context, result_builder)

      expect(client).not_to have_received(:update_account_holder)
      expect(result[:type]).to eq('Error')
      expect(result[:message]).to include('Nothing to update')
    end
  end
end
