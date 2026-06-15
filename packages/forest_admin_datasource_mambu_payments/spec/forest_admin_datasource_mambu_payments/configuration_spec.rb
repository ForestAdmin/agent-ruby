RSpec.describe ForestAdminDatasourceMambuPayments::Configuration do
  let(:valid_args) { { api_key: 'sk_test_xyz' } }

  describe '#initialize' do
    it 'accepts a valid api_key' do
      config = described_class.new(**valid_args)
      expect(config.api_key).to eq('sk_test_xyz')
    end

    it 'raises a ConfigurationError when api_key is nil' do
      expect { described_class.new(api_key: nil) }
        .to raise_error(ForestAdminDatasourceMambuPayments::ConfigurationError, /api_key/)
    end

    it 'raises a ConfigurationError when api_key is blank' do
      expect { described_class.new(api_key: '   ') }
        .to raise_error(ForestAdminDatasourceMambuPayments::ConfigurationError, /api_key/)
    end

    it 'defaults to the production base URL' do
      config = described_class.new(**valid_args)
      expect(config.base_url).to eq(described_class::DEFAULT_BASE_URL)
    end

    it 'switches to the sandbox base URL when sandbox: true' do
      config = described_class.new(**valid_args, sandbox: true)
      expect(config.base_url).to eq(described_class::SANDBOX_BASE_URL)
    end

    it 'honours an explicit base_url override (sandbox flag is ignored)' do
      config = described_class.new(**valid_args, base_url: 'https://example.test', sandbox: true)
      expect(config.base_url).to eq('https://example.test')
    end

    it 'keeps configurable open and overall timeouts' do
      config = described_class.new(**valid_args, open_timeout: 1, timeout: 2)
      expect(config.open_timeout).to eq(1)
      expect(config.timeout).to eq(2)
    end
  end

  describe '#url' do
    it 'appends the API version to the base URL' do
      config = described_class.new(**valid_args)
      expect(config.url).to eq("#{described_class::DEFAULT_BASE_URL}/v1")
    end

    it 'trims a trailing slash from base_url before appending the version' do
      config = described_class.new(**valid_args, base_url: 'https://example.test/')
      expect(config.url).to eq('https://example.test/v1')
    end
  end
end
