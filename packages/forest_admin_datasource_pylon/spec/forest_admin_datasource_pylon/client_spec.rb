RSpec.describe ForestAdminDatasourcePylon::Client do
  let(:configuration) do
    ForestAdminDatasourcePylon::Configuration.new(api_key: 'k', max_retries: 2, retry_interval: 0)
  end
  let(:client) { described_class.new(configuration) }
  let(:base) { configuration.url }

  def json(payload, status = 200)
    { status: status, body: payload.is_a?(String) ? payload : payload.to_json,
      headers: { 'Content-Type' => 'application/json' } }
  end

  describe 'authentication' do
    it 'sends the api key as a Bearer token' do
      stub_request(:get, "#{base}/me").to_return(json('data' => {}))

      client.me
      expect(WebMock).to have_requested(:get, "#{base}/me")
        .with(headers: { 'Authorization' => 'Bearer k', 'Accept' => 'application/json' })
    end

    it 'advertises a versioned user agent' do
      stub_request(:get, "#{base}/me").to_return(json('data' => {}))

      client.me
      expect(WebMock).to have_requested(:get, "#{base}/me")
        .with(headers: { 'User-Agent' => "forest_admin_datasource_pylon/#{ForestAdminDatasourcePylon::VERSION}" })
    end
  end

  describe '#me' do
    it 'unwraps the "data" envelope' do
      stub_request(:get, "#{base}/me").to_return(json('data' => { 'id' => 'org_1', 'name' => 'Acme' },
                                                      'request_id' => 'req_1'))

      expect(client.me).to eq('id' => 'org_1', 'name' => 'Acme')
    end

    it 'returns the body as-is when it is not wrapped' do
      stub_request(:get, "#{base}/me").to_return(json('id' => 'org_1'))

      expect(client.me).to eq('id' => 'org_1')
    end

    it 'returns nil when the response has an empty body' do
      stub_request(:get, "#{base}/me").to_return(status: 200, body: '')

      expect(client.me).to be_nil
    end

    it 'wraps an unauthorized response in an APIError carrying status and body' do
      stub_request(:get, "#{base}/me").to_return(json({ 'message' => 'invalid token' }, 401))

      expect { client.me }.to raise_error(ForestAdminDatasourcePylon::APIError) { |error|
        expect(error.message).to eq('Pylon API call failed: me: HTTP 401 invalid token')
        expect(error.status).to eq(401)
        expect(error.body).to eq('message' => 'invalid token')
      }
    end

    it 'appends the request_id when Pylon returns one' do
      stub_request(:get, "#{base}/me").to_return(json({ 'message' => 'boom', 'request_id' => 'req_42' }, 500))

      expect { client.me }
        .to raise_error(ForestAdminDatasourcePylon::APIError, /boom \(request_id: req_42\)/)
    end

    it 'reads the message out of a nested error object' do
      stub_request(:get, "#{base}/me").to_return(json({ 'error' => { 'message' => 'nested boom' } }, 422))

      expect { client.me }.to raise_error(ForestAdminDatasourcePylon::APIError, /HTTP 422 nested boom/)
    end

    it 'reads the message out of a plain string error' do
      stub_request(:get, "#{base}/me").to_return(json({ 'error' => 'flat boom' }, 422))

      expect { client.me }.to raise_error(ForestAdminDatasourcePylon::APIError, /HTTP 422 flat boom/)
    end

    it 'joins an errors array, accepting hashes and bare strings' do
      body = { 'errors' => [{ 'message' => 'first' }, { 'detail' => 'second' }, 'third'] }
      stub_request(:get, "#{base}/me").to_return(json(body, 422))

      expect { client.me }.to raise_error(ForestAdminDatasourcePylon::APIError, /first; second; third/)
    end

    it 'falls back to the raw body when it is not JSON' do
      stub_request(:get, "#{base}/me").to_return(status: 500, body: 'boom')

      expect { client.me }.to raise_error(ForestAdminDatasourcePylon::APIError, /HTTP 500 boom/)
    end

    it 'falls back to the serialized payload when no message field is recognised' do
      stub_request(:get, "#{base}/me").to_return(json({ 'unexpected' => true }, 400))

      expect { client.me }.to raise_error(ForestAdminDatasourcePylon::APIError, /HTTP 400 .*unexpected/)
    end

    it 'reports a connection failure without an HTTP status' do
      stub_request(:get, "#{base}/me").to_timeout

      expect { client.me }.to raise_error(ForestAdminDatasourcePylon::APIError) { |error|
        expect(error.status).to be_nil
        expect(error.message).to match(/Pylon API call failed: me: Faraday::ConnectionFailed/)
      }
    end

    it 'wraps a non-Faraday failure in an APIError' do
      allow(client).to receive(:extract_data).and_raise(KeyError, 'nope')
      stub_request(:get, "#{base}/me").to_return(json('data' => {}))

      expect { client.me }.to raise_error(ForestAdminDatasourcePylon::APIError, /me: KeyError: nope/)
    end
  end

  describe 'rate limiting' do
    it 'retries a 429 and returns the eventual success' do
      stub_request(:get, "#{base}/me")
        .to_return(json({ 'message' => 'slow down' }, 429))
        .then.to_return(json('data' => { 'id' => 'org_1' }))

      expect(client.me).to eq('id' => 'org_1')
      expect(WebMock).to have_requested(:get, "#{base}/me").twice
    end

    it 'retries a 503 and returns the eventual success' do
      stub_request(:get, "#{base}/me")
        .to_return(json({ 'message' => 'unavailable' }, 503))
        .then.to_return(json('data' => { 'id' => 'org_1' }))

      expect(client.me).to eq('id' => 'org_1')
      expect(WebMock).to have_requested(:get, "#{base}/me").twice
    end

    it 'gives up after the configured retry budget and raises the last error' do
      stub_request(:get, "#{base}/me").to_return(json({ 'message' => 'slow down' }, 429))

      expect { client.me }.to raise_error(ForestAdminDatasourcePylon::APIError) { |error|
        expect(error.status).to eq(429)
      }
      expect(WebMock).to have_requested(:get, "#{base}/me").times(3)
    end

    it 'does not retry a 404' do
      stub_request(:get, "#{base}/me").to_return(json({ 'message' => 'nope' }, 404))

      expect { client.me }.to raise_error(ForestAdminDatasourcePylon::APIError)
      expect(WebMock).to have_requested(:get, "#{base}/me").once
    end

    describe 'RETRY_IF' do
      it 'allows retrying a non-idempotent verb when Pylon answered 429' do
        expect(described_class::RETRY_IF.call({ status: 429 }, nil)).to be(true)
      end

      it 'refuses to retry a non-idempotent verb on any other failure' do
        expect(described_class::RETRY_IF.call({ status: 502 }, nil)).to be(false)
        expect(described_class::RETRY_IF.call({ status: nil }, nil)).to be(false)
      end
    end
  end
end
