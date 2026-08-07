RSpec.describe ForestAdminDatasourcePylon::Configuration do
  let(:valid_args) { { api_key: 'pk_test_xyz' } }

  describe '#initialize' do
    it 'accepts a valid api_key' do
      expect(described_class.new(**valid_args).api_key).to eq('pk_test_xyz')
    end

    it 'raises a ConfigurationError when api_key is nil' do
      expect { described_class.new(api_key: nil) }
        .to raise_error(ForestAdminDatasourcePylon::ConfigurationError, /api_key/)
    end

    it 'raises a ConfigurationError when api_key is blank' do
      expect { described_class.new(api_key: '   ') }
        .to raise_error(ForestAdminDatasourcePylon::ConfigurationError, /api_key/)
    end

    it 'defaults to the public Pylon base URL' do
      expect(described_class.new(**valid_args).base_url).to eq('https://api.usepylon.com')
    end

    it 'honours an explicit base_url override' do
      config = described_class.new(**valid_args, base_url: 'https://example.test')
      expect(config.base_url).to eq('https://example.test')
    end

    it 'defaults the timeouts' do
      config = described_class.new(**valid_args)
      expect([config.open_timeout, config.timeout]).to eq([5, 30])
    end

    it 'keeps configurable timeouts' do
      config = described_class.new(**valid_args, open_timeout: 1, timeout: 2)
      expect([config.open_timeout, config.timeout]).to eq([1, 2])
    end

    it 'defaults to a standard retry policy' do
      expect(described_class.new(**valid_args).retry_policy)
        .to be_a(ForestAdminDatasourcePylon::RetryPolicy)
    end

    it 'accepts an injected retry policy' do
      policy = ForestAdminDatasourcePylon::RetryPolicy.new(max_retries: 9)
      expect(described_class.new(**valid_args, retry_policy: policy).retry_policy).to be(policy)
    end
  end

  describe '#url' do
    it 'returns the base URL unversioned' do
      expect(described_class.new(**valid_args).url).to eq('https://api.usepylon.com')
    end

    it 'trims a trailing slash' do
      config = described_class.new(**valid_args, base_url: 'https://example.test/')
      expect(config.url).to eq('https://example.test')
    end
  end
end
