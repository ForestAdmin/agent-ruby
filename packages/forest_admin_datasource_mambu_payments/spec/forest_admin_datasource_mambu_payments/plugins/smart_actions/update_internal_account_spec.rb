RSpec.describe ForestAdminDatasourceMambuPayments::Plugins::SmartActions::UpdateInternalAccount do
  let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
  let(:datasource) { instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client) }
  let(:result_builder) { ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder.new }
  let(:collection_customizer) { ForestAdminDatasourceMambuPayments::PluginSupport::FakeCollection.new }
  let(:record_id_field) { 'mambu_internal_account_id' }

  def register(opts = {})
    described_class.new.run(nil, collection_customizer,
                            { datasource: datasource, record_id_field: record_id_field }.merge(opts))
    collection_customizer.registered[opts[:action_name] || described_class::NAME]
  end

  it 'PATCHes /internal_accounts/{id} with only the filled fields' do
    action = register
    allow(client).to receive(:update_internal_account)
    context = ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(
      records: [{ record_id_field => 'ia_1' }],
      form_values: { 'Name' => 'New', 'Holder name' => '', 'Account number' => '' }
    )

    action.execute.call(context, result_builder)

    expect(client).to have_received(:update_internal_account).with('ia_1', 'name' => 'New')
  end
end
