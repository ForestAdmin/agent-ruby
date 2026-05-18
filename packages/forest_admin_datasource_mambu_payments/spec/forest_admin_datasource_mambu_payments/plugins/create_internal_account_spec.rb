RSpec.describe ForestAdminDatasourceMambuPayments::Plugins::CreateInternalAccount do
  let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
  let(:datasource) { instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client) }
  let(:result_builder) { ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder.new }
  let(:collection_customizer) { ForestAdminDatasourceMambuPayments::PluginSupport::FakeCollection.new }

  def register(opts = {})
    described_class.new.run(nil, collection_customizer, { datasource: datasource }.merge(opts))
    collection_customizer.registered[opts[:action_name] || described_class::NAME]
  end

  it 'registers a SINGLE action with type/name/holder_name/account_number as required fields' do
    action = register
    expect(action.form.map { |f| f[:label] }).to eq(['Type', 'Name', 'Holder name', 'Account number'])
    expect(action.form.all? { |f| f[:is_required] }).to be(true)
  end

  it 'restricts Type to the documented enum values' do
    action = register
    type_field = action.form.find { |f| f[:label] == 'Type' }
    expect(type_field[:enum_values]).to eq(%w[own virtual])
  end

  it 'POSTs to /internal_accounts with the four required fields' do
    action = register
    allow(client).to receive(:create_internal_account).and_return({ 'id' => 'ia_1' })
    context = ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(form_values: {
                                                                                   'Type' => 'own',
                                                                                   'Name' => 'Main',
                                                                                   'Holder name' => 'Acme SAS',
                                                                                   'Account number' => 'FR76123'
                                                                                 })

    action.execute.call(context, result_builder)

    expect(client).to have_received(:create_internal_account).with(
      'type' => 'own', 'name' => 'Main', 'holder_name' => 'Acme SAS', 'account_number' => 'FR76123'
    )
  end
end
