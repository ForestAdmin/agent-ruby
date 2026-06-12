RSpec.describe ForestAdminDatasourceMambuPayments::Plugins::SmartActions::UpdateExternalAccount do
  let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
  let(:datasource) { instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client) }
  let(:result_builder) { ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder.new }
  let(:collection_customizer) { ForestAdminDatasourceMambuPayments::PluginSupport::FakeCollection.new }
  let(:record_id_field) { 'mambu_external_account_id' }

  def register(opts = {})
    described_class.new.run(nil, collection_customizer,
                            { datasource: datasource, record_id_field: record_id_field }.merge(opts))
    collection_customizer.registered[opts[:action_name] || described_class::NAME]
  end

  it 'PATCHes /external_accounts/{id} with only the filled fields' do
    action = register
    allow(client).to receive(:update_external_account)
    context = ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(
      records: [{ record_id_field => 'ea_1' }],
      form_values: { 'Holder name' => 'New', 'Account number' => '', 'Bank code' => '' }
    )

    action.execute.call(context, result_builder)

    expect(client).to have_received(:update_external_account).with('ea_1', 'holder_name' => 'New')
  end

  it 'raises ArgumentError without :record_id_field' do
    expect { described_class.new.run(nil, collection_customizer, datasource: datasource) }
      .to raise_error(ArgumentError, /record_id_field/)
  end
end
