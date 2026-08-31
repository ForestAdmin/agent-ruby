module ForestAdminDatasourceIntercom
  RSpec.describe Client do
    subject(:client) { described_class.new(configuration) }

    let(:retry_policy) { RetryPolicy.new(max_retries: 2, interval: 0) }
    let(:configuration) { Configuration.new(access_token: 's3cr3t', retry_policy: retry_policy, rate_limiter: nil) }
    let(:base) { configuration.url }

    def json(payload, status = 200, headers = {})
      { status: status,
        body: payload.is_a?(String) ? payload : payload.to_json,
        headers: { 'Content-Type' => 'application/json' }.merge(headers) }
    end

    describe 'authentication and version pinning' do
      before { stub_request(:get, "#{base}/me").to_return(json({ 'type' => 'admin' })) }

      it 'sends the access token as a bearer token' do
        client.me

        expect(WebMock).to have_requested(:get, "#{base}/me")
          .with(headers: { 'Authorization' => 'Bearer s3cr3t', 'Accept' => 'application/json' })
      end

      # Without the header the request follows the workspace's own default
      # version, which an operator can change on Intercom's side.
      it 'pins the API version on every request' do
        client.me

        expect(WebMock).to have_requested(:get, "#{base}/me").with(headers: { 'Intercom-Version' => '2.16' })
      end

      it 'advertises a versioned user agent' do
        client.me

        expect(WebMock).to have_requested(:get, "#{base}/me")
          .with(headers: { 'User-Agent' => "forest_admin_datasource_intercom/#{VERSION}" })
      end
    end

    describe '#me' do
      it 'returns the admin the token belongs to' do
        stub_request(:get, "#{base}/me").to_return(json('type' => 'admin', 'id' => '1', 'email' => 'a@b.test'))

        expect(client.me).to include('id' => '1', 'email' => 'a@b.test')
      end

      it 'reaches the regional host it was configured for' do
        eu = described_class.new(Configuration.new(access_token: 's3cr3t', region: :eu, rate_limiter: nil))
        stub_request(:get, 'https://api.eu.intercom.io/me').to_return(json('type' => 'admin'))

        eu.me

        expect(WebMock).to have_requested(:get, 'https://api.eu.intercom.io/me')
      end
    end

    describe 'the version Intercom actually served' do
      # Intercom echoes the version it served. A mismatch means the payloads may
      # not be the ones this datasource expects, which is worth saying out loud
      # -- and worth saying rather than raising: running against a version we
      # did not ask for beats not running.
      it 'warns when it differs from the pinned one' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_request(:get, "#{base}/me").to_return(json({ 'type' => 'admin' }, 200, 'intercom-version' => '2.14'))

        client.me

        expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/asked.*2\.16.*served 2\.14/m)
      end

      it 'stays quiet when the pin was honoured' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_request(:get, "#{base}/me").to_return(json({ 'type' => 'admin' }, 200, 'intercom-version' => '2.16'))

        client.me

        expect(ForestAdminDatasourceIntercom.logger).not_to have_received(:warn)
      end

      it 'stays quiet when Intercom echoes nothing' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_request(:get, "#{base}/me").to_return(json('type' => 'admin'))

        client.me

        expect(ForestAdminDatasourceIntercom.logger).not_to have_received(:warn)
      end
    end

    describe 'failures' do
      it "carries Intercom's status, parsed body and error text" do
        body = { 'type' => 'error.list', 'request_id' => 'req_1',
                 'errors' => [{ 'code' => 'unauthorized', 'message' => 'Access Token Invalid' }] }
        stub_request(:get, "#{base}/me").to_return(json(body, 401))

        expect { client.me }.to raise_error(APIError) { |error|
          expect(error.message).to eq('Intercom API call failed: me: HTTP 401 unauthorized: ' \
                                      'Access Token Invalid (request_id: req_1)')
          expect(error.status).to eq(401)
          expect(error.body).to eq(body)
        }
      end

      it 'joins the several errors one response can carry' do
        body = { 'errors' => [{ 'code' => 'parameter_invalid', 'message' => 'per_page' },
                              { 'code' => 'parameter_invalid', 'message' => 'starting_after' }] }
        stub_request(:get, "#{base}/me").to_return(json(body, 400))

        expect { client.me }.to raise_error(APIError, /per_page; parameter_invalid: starting_after/)
      end

      it 'falls back to the whole body when the shape is not the documented one' do
        stub_request(:get, "#{base}/me").to_return(json({ 'oops' => true }, 500))

        expect { client.me }.to raise_error(APIError, /\{"oops":true\}/)
      end

      it 'keeps a body that is not JSON at all, which is what a gateway answers' do
        stub_request(:get, "#{base}/me").to_return(status: 502, body: '<html>bad gateway</html>')

        expect { client.me }.to raise_error(APIError) { |error|
          expect(error.status).to eq(502)
          expect(error.body).to eq('<html>bad gateway</html>')
        }
      end

      # No status to report: the request never reached Intercom, so there is
      # nothing of its to surface.
      it 'reports a dropped connection without a status' do
        stub_request(:get, "#{base}/me").to_raise(Faraday::ConnectionFailed.new('closed'))

        expect { client.me }.to raise_error(APIError) { |error|
          expect(error.message).to include('Faraday::ConnectionFailed')
          expect(error.status).to be_nil
        }
      end

      it 'replays a 429 rather than surfacing it' do
        stub_request(:get, "#{base}/me")
          .to_return(json({ 'errors' => [{ 'code' => 'rate_limit_exceeded' }] }, 429))
          .then.to_return(json('type' => 'admin'))

        expect(client.me).to eq('type' => 'admin')
      end

      it 'gives up on a 429 that outlasts the retries, saying which endpoint' do
        stub_request(:get, "#{base}/me").to_return(json({ 'errors' => [{ 'code' => 'rate_limit_exceeded' }] }, 429))

        expect { client.me }.to raise_error(APIError, /me: HTTP 429 rate_limit_exceeded/)
      end

      # Whatever else goes wrong on the way, a caller of this client only ever
      # has to rescue APIError -- and the message names the operation, since a
      # failure with no endpoint in it is a failure nobody can place.
      it 'still names the operation when the failure is not one it expected' do
        stub_request(:get, "#{base}/me").to_raise(ArgumentError.new('unexpected'))

        expect { client.me }.to raise_error(APIError, /me: ArgumentError: unexpected/)
      end
    end

    describe '.bounded_per_page' do
      # Intercom answers `invalid_per_page` past 150 instead of clamping, so a
      # page size is bounded before it is sent or the list view breaks.
      it 'caps a page size at what Intercom accepts' do
        expect(described_class.bounded_per_page(200)).to eq(150)
      end

      it 'leaves an acceptable size alone' do
        expect(described_class.bounded_per_page(50)).to eq(50)
      end

      it 'asks for one record rather than none, an empty page being no answer' do
        expect([described_class.bounded_per_page(0), described_class.bounded_per_page(-5)]).to eq([1, 1])
      end
    end

    describe 'the boot connection' do
      # What is read while the datasource is being constructed waits far less
      # than a request that already has a page on screen: the wait there is
      # minutes of Rails boot the operator sits through.
      it 'honours the configured boot timeouts' do
        booted = described_class.new(Configuration.new(access_token: 's3cr3t', boot_open_timeout: 1, boot_timeout: 2))
        conn = booted.send(:boot_connection)

        expect(conn.options).to have_attributes(open_timeout: 1, timeout: 2)
      end

      it 'keeps the patience of a regular request on the regular connection' do
        expect(client.send(:connection).options).to have_attributes(open_timeout: 5, timeout: 30)
      end

      it 'reads through it when asked to' do
        stub_request(:get, "#{base}/me").to_return(json('type' => 'admin'))

        expect(client.me(boot: true)).to eq('type' => 'admin')
      end
    end

    describe 'pacing' do
      let(:limiter) { instance_double(RateLimiter, acquire: nil, observe: nil) }
      let(:paced) do
        described_class.new(Configuration.new(access_token: 's3cr3t', retry_policy: retry_policy,
                                              rate_limiter: limiter))
      end

      it 'asks the limiter for room, and feeds it the window back' do
        stub_request(:get, "#{base}/me").to_return(json({ 'type' => 'admin' }, 200,
                                                        'x-ratelimit-remaining' => '1666'))

        paced.me

        expect(limiter).to have_received(:acquire)
        expect(limiter).to have_received(:observe).with(hash_including('x-ratelimit-remaining' => '1666'))
      end

      # The throttle sits inside the retry, so a replay waits for the window
      # like a first attempt rather than going out on a budget already spent.
      it 'asks again for every replay, not once per call' do
        stub_request(:get, "#{base}/me")
          .to_return(json({}, 429)).then.to_return(json('type' => 'admin'))

        paced.me

        expect(limiter).to have_received(:acquire).twice
      end
    end

    describe '#inspect' do
      it 'never prints the token its connections carry' do
        expect(client.inspect).to include(base)
        expect(client.inspect).not_to include('s3cr3t')
      end
    end
  end
end
