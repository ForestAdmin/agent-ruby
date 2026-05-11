RSpec.describe ForestAdminDatasourceMambuPayments::Datasource do
  let(:valid_args) { { api_key: 'k' } }

  it 'builds with valid credentials and exposes a client' do
    ds = described_class.new(**valid_args)
    expect(ds.client).to be_a(ForestAdminDatasourceMambuPayments::Client)
    expect(ds.configuration.api_key).to eq('k')
  end

  it 'forwards the sandbox flag to the configuration' do
    ds = described_class.new(**valid_args, sandbox: true)
    expect(ds.configuration.base_url)
      .to eq(ForestAdminDatasourceMambuPayments::Configuration::SANDBOX_BASE_URL)
  end

  it 'raises ConfigurationError when api_key is missing' do
    expect { described_class.new(api_key: nil) }
      .to raise_error(ForestAdminDatasourceMambuPayments::ConfigurationError)
  end

  it 'registers all Mambu Payments collections' do
    ds = described_class.new(**valid_args)
    expect(ds.collections.keys).to contain_exactly(
      'MambuConnectedAccount', 'MambuPaymentOrder', 'MambuTransaction', 'MambuBalance',
      'MambuAccountHolder', 'MambuExternalAccount', 'MambuInternalAccount',
      'MambuIncomingPayment', 'MambuDirectDebitMandate', 'MambuExpectedPayment'
    )
  end
end
