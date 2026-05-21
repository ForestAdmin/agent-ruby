RSpec.describe ForestAdminDatasourceMambuPayments::Plugins::SmartActions::CancelPaymentOrder do
  let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
  let(:datasource) { instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client) }
  let(:result_builder) { ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder.new }
  let(:collection_customizer) { ForestAdminDatasourceMambuPayments::PluginSupport::FakeCollection.new }
  let(:record_id_field) { 'mambu_payment_order_id' }

  def register(opts = {})
    described_class.new.run(nil, collection_customizer,
                            { datasource: datasource, record_id_field: record_id_field }.merge(opts))
    collection_customizer.registered
  end

  it 'registers both single and bulk by default' do
    register
    expect(collection_customizer.registered.keys).to contain_exactly(
      'Cancel Mambu payment order', 'Cancel selected Mambu payment orders'
    )
  end

  it 'exposes an optional Reason field on the form' do
    register
    action = collection_customizer.registered['Cancel Mambu payment order']
    field = action.form.first
    expect(field[:label]).to eq('Reason')
    expect(field[:is_required]).to be_falsey
  end

  it 'POSTs /payment_orders/{id}/cancel with the reason when provided' do
    allow(client).to receive(:cancel_payment_order)
    single = register(scopes: %i[single])['Cancel Mambu payment order']
    context = ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(
      records: [{ record_id_field => 'po_1' }],
      form_values: { 'Reason' => 'AC01' }
    )

    single.execute.call(context, result_builder)

    expect(client).to have_received(:cancel_payment_order).with('po_1', 'reason' => 'AC01')
  end

  it 'omits the reason from the payload when blank' do
    allow(client).to receive(:cancel_payment_order)
    single = register(scopes: %i[single])['Cancel Mambu payment order']
    context = ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(
      records: [{ record_id_field => 'po_1' }], form_values: { 'Reason' => '' }
    )

    single.execute.call(context, result_builder)

    expect(client).to have_received(:cancel_payment_order).with('po_1', {})
  end
end
