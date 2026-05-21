RSpec.describe ForestAdminDatasourceMambuPayments::Plugins::SmartActions::ApprovePaymentOrder do
  let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
  let(:datasource) { instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client) }
  let(:result_builder) { ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder.new }
  let(:collection_customizer) { ForestAdminDatasourceMambuPayments::PluginSupport::FakeCollection.new }
  let(:record_id_field) { 'mambu_payment_order_id' }
  let(:action_scope) { ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope }

  def register(opts = {})
    described_class.new.run(nil, collection_customizer,
                            { datasource: datasource, record_id_field: record_id_field }.merge(opts))
    collection_customizer.registered
  end

  it 'registers both single and bulk by default with the right scopes' do
    register
    registered = collection_customizer.registered
    expect(registered.keys).to contain_exactly(
      'Approve Mambu payment order', 'Approve selected Mambu payment orders'
    )
    expect(registered['Approve Mambu payment order'].scope).to eq(action_scope::SINGLE)
    expect(registered['Approve selected Mambu payment orders'].scope).to eq(action_scope::BULK)
  end

  it 'POSTs /payment_orders/{id}/approve for each id and reports success' do
    allow(client).to receive(:approve_payment_order)
    bulk = register(scopes: %i[bulk])['Approve selected Mambu payment orders']
    context = ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(
      records: [1, 2, 3].map { |id| { record_id_field => id } }
    )

    result = bulk.execute.call(context, result_builder)

    [1, 2, 3].each { |id| expect(client).to have_received(:approve_payment_order).with(id) }
    expect(result[:message]).to include('3 payment orders approved')
  end

  it 'returns an Error when all ids fail' do
    allow(client).to receive(:approve_payment_order).and_raise(StandardError, 'wrong status')
    allow(ForestAdminDatasourceMambuPayments.logger).to receive(:warn)
    bulk = register(scopes: %i[bulk])['Approve selected Mambu payment orders']
    context = ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(
      records: [{ record_id_field => 'po_1' }]
    )

    result = bulk.execute.call(context, result_builder)

    expect(result[:type]).to eq('Error')
    expect(result[:message]).to include('Failed to approve', 'wrong status')
  end
end
