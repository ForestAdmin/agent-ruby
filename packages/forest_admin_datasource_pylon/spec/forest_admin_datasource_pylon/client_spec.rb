RSpec.describe ForestAdminDatasourcePylon::Client do
  let(:retry_policy) { ForestAdminDatasourcePylon::RetryPolicy.new(max_retries: 2, interval: 0) }
  let(:configuration) { ForestAdminDatasourcePylon::Configuration.new(api_key: 'k', retry_policy: retry_policy) }
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

    it 'keeps the request_id even when the message is truncated' do
      body = { 'message' => 'x' * 900, 'request_id' => 'req_42' }
      stub_request(:get, "#{base}/me").to_return(json(body, 500))

      expect { client.me }.to raise_error(ForestAdminDatasourcePylon::APIError, /\(request_id: req_42\)\z/)
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

    # Callers branch on `status`, so an already-mapped error has to come back
    # untouched rather than be re-wrapped by the generic StandardError arm.
    it 'lets an already-mapped APIError through with its status intact' do
      mapped = ForestAdminDatasourcePylon::APIError.new('boom', status: 404, body: { 'message' => 'boom' })
      allow(client).to receive(:extract_data).and_raise(mapped)
      stub_request(:get, "#{base}/me").to_return(json('data' => {}))

      expect { client.me }.to raise_error(ForestAdminDatasourcePylon::APIError) { |error|
        expect(error).to be(mapped)
        expect(error.status).to eq(404)
      }
    end
  end

  describe '#search_issues' do
    it 'posts the limit and returns the records' do
      stub_request(:post, "#{base}/issues/search").to_return(json('data' => [{ 'id' => 'i1' }]))

      page = client.search_issues(limit: 2)

      expect(page.records).to eq([{ 'id' => 'i1' }])
      expect(WebMock).to have_requested(:post, "#{base}/issues/search").with(body: { 'limit' => 2 })
    end

    it 'omits cursor, filter and search_text when they are not provided' do
      stub_request(:post, "#{base}/issues/search").to_return(json('data' => []))

      client.search_issues(limit: 5, cursor: nil, filter: nil, search_text: '')

      expect(WebMock).to have_requested(:post, "#{base}/issues/search").with(body: { 'limit' => 5 })
    end

    it 'forwards cursor, filter and search_text when provided' do
      stub_request(:post, "#{base}/issues/search").to_return(json('data' => []))
      filter = { 'field' => 'state', 'operator' => 'equals', 'values' => ['new'] }

      client.search_issues(limit: 5, cursor: 'c1', filter: filter, search_text: 'boom')

      expect(WebMock).to have_requested(:post, "#{base}/issues/search")
        .with(body: { 'limit' => 5, 'cursor' => 'c1', 'filter' => filter, 'search_text' => 'boom' })
    end

    it 'clamps the limit to the API maximum' do
      stub_request(:post, "#{base}/issues/search").to_return(json('data' => []))

      client.search_issues(limit: 99_999)

      expect(WebMock).to have_requested(:post, "#{base}/issues/search")
        .with(body: { 'limit' => described_class::MAX_SEARCH_LIMIT })
    end

    it 'raises the limit to 1 when it is zero or negative' do
      stub_request(:post, "#{base}/issues/search").to_return(json('data' => []))

      client.search_issues(limit: 0)

      expect(WebMock).to have_requested(:post, "#{base}/issues/search").with(body: { 'limit' => 1 })
    end

    it 'exposes the cursor when a next page is advertised' do
      stub_request(:post, "#{base}/issues/search")
        .to_return(json('data' => [], 'pagination' => { 'cursor' => 'c2', 'has_next_page' => true }))

      expect(client.search_issues(limit: 1).next_cursor).to eq('c2')
    end

    # Pylon omits the block entirely on the last page, so absence is the
    # common case rather than the edge case.
    it 'reports no next cursor when the pagination block is absent' do
      stub_request(:post, "#{base}/issues/search").to_return(json('data' => [{ 'id' => 'i1' }]))

      expect(client.search_issues(limit: 1).next_cursor).to be_nil
    end

    it 'reports no next cursor when has_next_page is false' do
      stub_request(:post, "#{base}/issues/search")
        .to_return(json('data' => [], 'pagination' => { 'cursor' => 'c2', 'has_next_page' => false }))

      expect(client.search_issues(limit: 1).next_cursor).to be_nil
    end

    it 'reports no next cursor when the advertised cursor is empty' do
      stub_request(:post, "#{base}/issues/search")
        .to_return(json('data' => [], 'pagination' => { 'cursor' => '', 'has_next_page' => true }))

      expect(client.search_issues(limit: 1).next_cursor).to be_nil
    end

    it 'returns no records when the payload carries none' do
      stub_request(:post, "#{base}/issues/search").to_return(json('data' => nil))

      expect(client.search_issues(limit: 1).records).to eq([])
    end

    it 'wraps a failure in an APIError naming the endpoint' do
      stub_request(:post, "#{base}/issues/search").to_return(json({ 'message' => 'bad filter' }, 400))

      expect { client.search_issues(limit: 1) }
        .to raise_error(ForestAdminDatasourcePylon::APIError, %r{issues/search: HTTP 400 bad filter})
    end
  end

  describe '#fetch_issue' do
    it 'unwraps the issue' do
      stub_request(:get, "#{base}/issues/i1").to_return(json('data' => { 'id' => 'i1', 'number' => 1 }))

      expect(client.fetch_issue('i1')).to eq('id' => 'i1', 'number' => 1)
    end

    it 'accepts an issue number as well as a uuid' do
      stub_request(:get, "#{base}/issues/42").to_return(json('data' => { 'id' => 'i1', 'number' => 42 }))

      expect(client.fetch_issue(42)).to include('number' => 42)
    end

    it 'wraps a missing issue in a 404 APIError' do
      stub_request(:get, "#{base}/issues/nope").to_return(json({ 'message' => 'not found' }, 404))

      expect { client.fetch_issue('nope') }.to raise_error(ForestAdminDatasourcePylon::APIError) { |error|
        expect(error.status).to eq(404)
      }
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

    it 'retries a dropped connection' do
      stub_request(:get, "#{base}/me").to_timeout.then.to_return(json('data' => { 'id' => 'org_1' }))

      expect(client.me).to eq('id' => 'org_1')
      expect(WebMock).to have_requested(:get, "#{base}/me").twice
    end

    # Regression: max_interval used to be hardcoded to 5s. faraday-retry gives up
    # outright when Retry-After exceeds max_interval, so a Pylon 429 carrying a
    # per-minute Retry-After silently performed zero retries.
    describe 'Retry-After' do
      it 'honours a Retry-After that fits within the cap' do
        stub_request(:get, "#{base}/me")
          .to_return(status: 429, headers: { 'Retry-After' => '0' })
          .then.to_return(json('data' => { 'id' => 'org_1' }))

        expect(client.me).to eq('id' => 'org_1')
        expect(WebMock).to have_requested(:get, "#{base}/me").twice
      end

      it 'gives up without retrying when Retry-After exceeds the cap' do
        impatient = ForestAdminDatasourcePylon::Configuration.new(
          api_key: 'k', retry_policy: ForestAdminDatasourcePylon::RetryPolicy.new(interval: 0, max_interval: 1)
        )
        stub_request(:get, "#{base}/me").to_return(status: 429, headers: { 'Retry-After' => '5' })

        expect { described_class.new(impatient).me }.to raise_error(ForestAdminDatasourcePylon::APIError)
        expect(WebMock).to have_requested(:get, "#{base}/me").once
      end
    end
  end
end
