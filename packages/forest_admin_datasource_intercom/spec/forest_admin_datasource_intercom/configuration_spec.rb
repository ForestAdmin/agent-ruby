module ForestAdminDatasourceIntercom
  RSpec.describe Configuration do
    subject(:configuration) { described_class.new(access_token: 's3cr3t') }

    it 'defaults to the US host, since that is where a workspace lands unasked' do
      expect(configuration.url).to eq('https://api.intercom.io')
    end

    it 'pins the API version the spike ran against' do
      expect(configuration.api_version).to eq('2.16')
    end

    it 'points at the regional host it is given' do
      expect(described_class.new(access_token: 's3cr3t', region: :eu).url).to eq('https://api.eu.intercom.io')
    end

    it 'takes the region as a string too' do
      expect(described_class.new(access_token: 's3cr3t', region: 'AU').url).to eq('https://api.au.intercom.io')
    end

    it 'lets an explicit base_url win over the region, for a proxy or a mock server' do
      configured = described_class.new(access_token: 's3cr3t', region: :eu, base_url: 'https://intercom.test/api/')

      expect(configured.url).to eq('https://intercom.test/api')
    end

    it 'reports the subpath a base_url is mounted under' do
      configured = described_class.new(access_token: 's3cr3t', base_url: 'https://intercom.test/api')

      expect(configured.base_path).to eq('/api')
    end

    it 'reports no subpath against the API itself' do
      expect(configuration.base_path).to eq('')
    end

    describe 'validation' do
      it 'refuses a missing access token' do
        expect { described_class.new(access_token: nil) }
          .to raise_error(ConfigurationError, /missing required config: access_token/)
      end

      it 'refuses a blank access token' do
        expect { described_class.new(access_token: '  ') }
          .to raise_error(ConfigurationError, /access_token/)
      end

      it 'names the regions it knows when handed one it does not' do
        expect { described_class.new(access_token: 's3cr3t', region: :moon) }
          .to raise_error(ConfigurationError, /unknown region :moon.*:us, :eu, :au/m)
      end

      # A relative base_url makes Faraday resolve paths against the working
      # directory, which surfaces much later as a failure naming nothing.
      it 'refuses a base_url that is not absolute' do
        expect { described_class.new(access_token: 's3cr3t', base_url: 'api.intercom.io') }
          .to raise_error(ConfigurationError, /must be an absolute http\(s\) url/)
      end

      it 'refuses a base_url that is not a url at all' do
        expect { described_class.new(access_token: 's3cr3t', base_url: 'http://[bad') }
          .to raise_error(ConfigurationError, /not a valid url/)
      end

      it 'refuses an empty api_version, which would let the workspace default decide' do
        expect { described_class.new(access_token: 's3cr3t', api_version: '') }
          .to raise_error(ConfigurationError, /api_version cannot be empty/)
      end
    end

    describe 'defaults' do
      it 'paces requests and retries unless told otherwise' do
        expect(configuration).to have_attributes(rate_limiter: an_instance_of(RateLimiter),
                                                 retry_policy: an_instance_of(RetryPolicy))
      end

      it 'is patient on a request and impatient on the boot' do
        expect(configuration).to have_attributes(timeout: 30, open_timeout: 5, boot_timeout: 10,
                                                 boot_open_timeout: 3)
      end

      it 'takes the pacing out of the stack when handed no limiter' do
        expect(described_class.new(access_token: 's3cr3t', rate_limiter: nil).rate_limiter).to be_nil
      end
    end

    describe '#inspect' do
      it 'never prints the bearer token' do
        expect(configuration.inspect).to include('[FILTERED]')
        expect(configuration.inspect).not_to include('s3cr3t')
      end

      it 'still names the host and version, which is what one inspects it for' do
        expect(configuration.inspect).to include('https://api.intercom.io', '2.16')
      end
    end
  end
end
