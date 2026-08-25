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

    it 'throttles by default' do
      expect(described_class.new(**valid_args).rate_limiter)
        .to be_a(ForestAdminDatasourcePylon::RateLimiter)
    end

    it 'accepts an injected limiter' do
      limiter = ForestAdminDatasourcePylon::RateLimiter.new(max_wait: 1)
      expect(described_class.new(**valid_args, rate_limiter: limiter).rate_limiter).to be(limiter)
    end

    # One limiter per configuration, so per token: Pylon meters the token, and
    # two agents holding different ones do not share a budget.
    it 'gives each configuration its own window' do
      first = described_class.new(**valid_args)
      expect(described_class.new(**valid_args).rate_limiter).not_to be(first.rate_limiter)
    end

    it 'takes the throttling out of the stack when handed nil' do
      expect(described_class.new(**valid_args, rate_limiter: nil).rate_limiter).to be_nil
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

  describe '#base_path' do
    it 'is empty against the API itself, which mounts its endpoints on the host' do
      expect(described_class.new(**valid_args).base_path).to eq('')
    end

    # `RateLimits` is keyed on the endpoint, so a base url mounted under a
    # subpath — an egress proxy, a mock server — has to have that prefix taken
    # off a path before the table is asked.
    it 'is the prefix a base url mounted under a subpath puts in front of every path' do
      config = described_class.new(**valid_args, base_url: 'https://proxy.test/pylon/v1')
      expect(config.base_path).to eq('/pylon/v1')
    end

    it 'carries no trailing slash, `url` having trimmed it' do
      config = described_class.new(**valid_args, base_url: 'https://proxy.test/pylon/')
      expect(config.base_path).to eq('/pylon')
    end
  end
end
