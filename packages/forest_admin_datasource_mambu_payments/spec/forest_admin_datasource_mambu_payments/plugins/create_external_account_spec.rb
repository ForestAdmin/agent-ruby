RSpec.describe ForestAdminDatasourceMambuPayments::Plugins::CreateExternalAccount do
  let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
  let(:datasource) { instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client) }
  let(:result_builder) { ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder.new }
  let(:collection_customizer) { ForestAdminDatasourceMambuPayments::PluginSupport::FakeCollection.new }

  def register(opts = {})
    described_class.new.run(nil, collection_customizer, { datasource: datasource }.merge(opts))
    collection_customizer.registered[opts[:action_name] || described_class::NAME]
  end

  it 'registers a SINGLE action with holder_name, account_number, bank_code as required fields' do
    action = register
    expect(action.scope).to eq(ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope::SINGLE)
    expect(action.form.map { |f| f[:label] }).to eq(['Holder name', 'Account number', 'Bank code'])
    expect(action.form.all? { |f| f[:is_required] }).to be(true)
  end

  it 'POSTs to /external_accounts with the form values' do
    action = register
    allow(client).to receive(:create_external_account).and_return({ 'id' => 'ea_9' })
    context = ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(form_values: {
                                                                                   'Holder name' => 'Acme',
                                                                                   'Account number' => 'FR76123',
                                                                                   'Bank code' => 'BNPAFRPP'
                                                                                 })

    result = action.execute.call(context, result_builder)

    expect(client).to have_received(:create_external_account).with(
      'holder_name' => 'Acme', 'account_number' => 'FR76123', 'bank_code' => 'BNPAFRPP'
    )
    expect(result[:type]).to eq('Success')
    expect(result[:message]).to include('External account #ea_9 created')
  end

  it 'raises ArgumentError without :datasource' do
    expect { described_class.new.run(nil, collection_customizer, {}) }
      .to raise_error(ArgumentError, /datasource/)
  end
end
