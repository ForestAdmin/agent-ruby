RSpec.describe ForestAdminDatasourceMambuPayments::Plugins::CreateAccountHolder do
  let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
  let(:datasource) { instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client) }
  let(:result_builder) { ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder.new }
  let(:collection_customizer) { ForestAdminDatasourceMambuPayments::PluginSupport::FakeCollection.new }

  def register(opts = {})
    described_class.new.run(nil, collection_customizer, { datasource: datasource }.merge(opts))
    collection_customizer.registered[opts[:action_name] || described_class::NAME]
  end

  describe '#run' do
    it 'registers a SINGLE-scoped action under the default name with a single required field' do
      action = register

      expect(collection_customizer.registered.keys).to contain_exactly(described_class::NAME)
      expect(action.scope).to eq(ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope::SINGLE)
      expect(action.form.map { |f| f[:label] }).to eq(['Name'])
      expect(action.form.first[:is_required]).to be(true)
    end

    it 'honors :action_name to override the displayed name' do
      register(action_name: 'New holder')
      expect(collection_customizer.registered.keys).to include('New holder')
    end

    it 'raises ArgumentError without :datasource' do
      expect { described_class.new.run(nil, collection_customizer, {}) }
        .to raise_error(ArgumentError, /datasource/)
    end

    it 'raises ArgumentError without a collection_customizer' do
      expect { described_class.new.run(nil, nil, datasource: datasource) }
        .to raise_error(ArgumentError, /collection/)
    end
  end

  describe 'executor' do
    it 'POSTs to /account_holders with the Name from the form and surfaces the new id' do
      action = register
      allow(client).to receive(:create_account_holder).and_return({ 'id' => 'ah_1' })
      context = ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(form_values: { 'Name' => 'Acme' })

      result = action.execute.call(context, result_builder)

      expect(client).to have_received(:create_account_holder).with('name' => 'Acme')
      expect(result[:type]).to eq('Success')
      expect(result[:message]).to include('Account holder #ah_1 created')
    end

    it 'writes back the new id to the host record when :result_field is configured' do
      action = register(result_field: 'mambu_account_holder_id')
      allow(client).to receive(:create_account_holder).and_return({ 'id' => 'ah_42' })
      collection = instance_double('Collection', update: true) # rubocop:disable RSpec/VerifiedDoubleReference
      context = ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(
        form_values: { 'Name' => 'Acme' }, collection: collection, filter: :stub_filter
      )

      action.execute.call(context, result_builder)

      expect(collection).to have_received(:update).with(:stub_filter, 'mambu_account_holder_id' => 'ah_42')
    end

    it 'surfaces a warning in the success message when the write-back fails' do
      action = register(result_field: 'mambu_account_holder_id')
      allow(client).to receive(:create_account_holder).and_return({ 'id' => 'ah_42' })
      collection = instance_double('Collection') # rubocop:disable RSpec/VerifiedDoubleReference
      allow(collection).to receive(:update).and_raise(StandardError, 'db down')
      allow(ForestAdminDatasourceMambuPayments.logger).to receive(:warn)
      context = ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(
        form_values: { 'Name' => 'Acme' }, collection: collection, filter: :stub_filter
      )

      result = action.execute.call(context, result_builder)

      expect(result[:type]).to eq('Success')
      expect(result[:message]).to include('warning', 'db down')
    end
  end
end
