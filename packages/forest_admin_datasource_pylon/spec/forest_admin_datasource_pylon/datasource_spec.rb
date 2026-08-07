RSpec.describe ForestAdminDatasourcePylon::Datasource do
  let(:datasource) { described_class.new(api_key: 'k') }

  it 'builds a configuration from the api key' do
    expect(datasource.configuration.api_key).to eq('k')
    expect(datasource.configuration.url).to eq(ForestAdminDatasourcePylon::Configuration::DEFAULT_BASE_URL)
  end

  it 'forwards the remaining options to the configuration' do
    custom = described_class.new(api_key: 'k', base_url: 'https://pylon.test/', timeout: 3)

    expect(custom.configuration.url).to eq('https://pylon.test')
    expect(custom.configuration.timeout).to eq(3)
  end

  it 'exposes a client built on that configuration' do
    expect(datasource.client).to be_a(ForestAdminDatasourcePylon::Client)
  end

  it 'registers the issue collection' do
    expect(datasource.collections.keys).to eq(['PylonIssue'])
    expect(datasource.get_collection('PylonIssue')).to be_a(ForestAdminDatasourcePylon::Collections::Issue)
  end

  it 'refuses to build without an api key' do
    expect { described_class.new(api_key: nil) }.to raise_error(ForestAdminDatasourcePylon::ConfigurationError)
  end

  # Nothing is introspected at boot yet: registering collections must not hit
  # the API, so an agent boots even when Pylon is unreachable.
  it 'does not call the API while registering collections' do
    datasource

    expect(WebMock).not_to have_requested(:any, /usepylon/)
  end
end
