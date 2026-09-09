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

    # `URI::HTTPS` is a `URI::HTTP`, so a cleartext base_url is accepted -- a
    # mock server is one, and that is half of what the parameter is for. What it
    # costs is the bearer header crossing that network in clear, and the token
    # reads the whole workspace.
    describe 'a cleartext base_url' do
      before { allow(ForestAdminDatasourceIntercom.logger).to receive(:warn) }

      it 'is accepted, and says the access token travels in clear over it' do
        described_class.new(access_token: 's3cr3t', base_url: 'http://proxy.internal/intercom')

        expect(ForestAdminDatasourceIntercom.logger)
          .to have_received(:warn).with(/is not https, and every request carries the Intercom access token/)
      end

      it 'says nothing about a loopback host, which is nobody else s network' do
        described_class.new(access_token: 's3cr3t', base_url: 'http://localhost:4010')
        described_class.new(access_token: 's3cr3t', base_url: 'http://intercom.localhost')

        expect(ForestAdminDatasourceIntercom.logger).not_to have_received(:warn)
      end

      it 'says nothing about https' do
        described_class.new(access_token: 's3cr3t', base_url: 'https://intercom.test')

        expect(ForestAdminDatasourceIntercom.logger).not_to have_received(:warn)
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

      # A credentialed egress proxy is the other reason to set a base_url, and
      # `URI` accepts its credentials in the url: printing it verbatim would put
      # a second secret exactly where this keeps the first one from going.
      it 'masks the credentials of a base_url that carries them' do
        configured = described_class.new(access_token: 's3cr3t', base_url: 'https://bob:hunter2@proxy.test/api')

        expect(configured.inspect).not_to include('hunter2', 'bob')
        expect(configured.inspect).to include('https://[FILTERED]@proxy.test/api')
      end
    end
  end
end
