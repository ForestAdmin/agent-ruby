RSpec.describe ForestAdminDatasourceMambuPayments::Plugins::CreatePaymentOrder do
  let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
  let(:datasource) { instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client) }
  let(:result_builder) { ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder.new }
  let(:collection_customizer) { ForestAdminDatasourceMambuPayments::PluginSupport::FakeCollection.new }

  def register(opts = {})
    described_class.new.run(nil, collection_customizer, { datasource: datasource }.merge(opts))
    collection_customizer.registered[opts[:action_name] || described_class::NAME]
  end

  it 'registers a SINGLE action with the six required Numeral fields' do
    action = register
    labels = action.form.map { |f| f[:label] }
    expect(labels).to eq(['Type', 'Direction', 'Amount', 'Currency', 'Reference', 'Connected account id'])
    expect(action.form.all? { |f| f[:is_required] }).to be(true)
  end

  it 'restricts Direction to credit/debit and uses Number for Amount' do
    action = register
    direction = action.form.find { |f| f[:label] == 'Direction' }
    amount    = action.form.find { |f| f[:label] == 'Amount' }
    expect(direction[:enum_values]).to eq(%w[credit debit])
    expect(amount[:type]).to eq(ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType::NUMBER)
  end

  it 'POSTs to /payment_orders with the parsed integer amount' do
    action = register
    allow(client).to receive(:create_payment_order).and_return({ 'id' => 'po_1' })
    context = ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(form_values: {
                                                                                   'Type' => 'sepa_credit_transfer',
                                                                                   'Direction' => 'credit',
                                                                                   'Amount' => '1500',
                                                                                   'Currency' => 'EUR',
                                                                                   'Reference' => 'INV-42',
                                                                                   'Connected account id' => 'ca_1'
                                                                                 })

    result = action.execute.call(context, result_builder)

    expect(client).to have_received(:create_payment_order).with(hash_including(
                                                                  'type' => 'sepa_credit_transfer',
                                                                  'direction' => 'credit',
                                                                  'amount' => 1500,
                                                                  'currency' => 'EUR',
                                                                  'reference' => 'INV-42',
                                                                  'connected_account_id' => 'ca_1'
                                                                ))
    expect(result[:message]).to include('Payment order #po_1 created')
  end

  it 'rejects a non-integer Amount' do
    action = register
    allow(client).to receive(:create_payment_order)
    context = ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(form_values: {
                                                                                   'Type' => 'sepa_credit_transfer',
                                                                                   'Direction' => 'credit',
                                                                                   'Amount' => 'abc',
                                                                                   'Currency' => 'EUR',
                                                                                   'Reference' => 'r',
                                                                                   'Connected account id' => 'ca_1'
                                                                                 })

    result = action.execute.call(context, result_builder)

    expect(client).not_to have_received(:create_payment_order)
    expect(result[:type]).to eq('Error')
    expect(result[:message]).to include('Amount')
  end
end
