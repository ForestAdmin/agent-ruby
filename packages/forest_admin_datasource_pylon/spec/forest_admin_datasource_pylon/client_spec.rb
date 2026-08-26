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

    it 'escapes an id that would otherwise alter the request path' do
      stub_request(:get, "#{base}/issues/..%2Fme").to_return(json('data' => nil))

      client.fetch_issue('../me')

      expect(WebMock).to have_requested(:get, "#{base}/issues/..%2Fme")
    end

    it 'wraps a missing issue in a 404 APIError' do
      stub_request(:get, "#{base}/issues/nope").to_return(json({ 'message' => 'not found' }, 404))

      expect { client.fetch_issue('nope') }.to raise_error(ForestAdminDatasourcePylon::APIError) { |error|
        expect(error.status).to eq(404)
      }
    end
  end

  describe '#fetch_issue_messages' do
    let(:logger) { instance_double(Logger, warn: nil) }

    def page(records, cursor: nil)
      body = { 'data' => records }
      body['pagination'] = { 'cursor' => cursor, 'has_next_page' => true } if cursor
      json(body)
    end

    it 'returns the whole thread of an issue' do
      stub_request(:get, "#{base}/issues/i1/messages").to_return(page([{ 'id' => 'm1' }, { 'id' => 'm2' }]))

      expect(client.fetch_issue_messages('i1')).to eq([{ 'id' => 'm1' }, { 'id' => 'm2' }])
    end

    # Omitting `limit` is what makes Pylon answer with every message at once;
    # asking for a page would hand back the oldest ones and cut off the rest.
    it 'sends no limit, so Pylon answers with every message in one request' do
      stub_request(:get, "#{base}/issues/i1/messages").to_return(page([]))

      client.fetch_issue_messages('i1')

      expect(WebMock).to have_requested(:get, "#{base}/issues/i1/messages").with(query: {}).once
    end

    it 'escapes an id that would otherwise alter the request path' do
      stub_request(:get, "#{base}/issues/..%2Fme/messages").to_return(page([]))

      client.fetch_issue_messages('../me')

      expect(WebMock).to have_requested(:get, "#{base}/issues/..%2Fme/messages")
    end

    it 'follows the cursor when Pylon paginates the thread anyway' do
      stub_request(:get, "#{base}/issues/i1/messages").with(query: {})
                                                      .to_return(page([{ 'id' => 'm1' }], cursor: 'c1'))
      stub_request(:get, "#{base}/issues/i1/messages").with(query: { 'cursor' => 'c1' })
                                                      .to_return(page([{ 'id' => 'm2' }]))

      expect(client.fetch_issue_messages('i1')).to eq([{ 'id' => 'm1' }, { 'id' => 'm2' }])
    end

    it 'stops on a cursor that does not move' do
      stub_request(:get, "#{base}/issues/i1/messages").with(query: { 'cursor' => 'c1' })
                                                      .to_return(page([{ 'id' => 'm2' }], cursor: 'c1'))
      stub_request(:get, "#{base}/issues/i1/messages").with(query: {})
                                                      .to_return(page([{ 'id' => 'm1' }], cursor: 'c1'))

      expect(client.fetch_issue_messages('i1').size).to eq(2)
    end

    it 'stops on an empty page' do
      stub_request(:get, "#{base}/issues/i1/messages").to_return(page([], cursor: 'c1'))

      expect(client.fetch_issue_messages('i1')).to eq([])
      expect(WebMock).to have_requested(:get, "#{base}/issues/i1/messages").once
    end

    it 'caps a thread Pylon never stops paginating, and says so' do
      allow(ForestAdminDatasourcePylon).to receive(:logger).and_return(logger)
      served = 0
      stub_request(:get, %r{/issues/i1/messages}).to_return do
        served += 1
        page([{ 'id' => "m#{served}" }], cursor: "c#{served}")
      end

      client.fetch_issue_messages('i1')

      expect(served).to eq(described_class::MAX_COLLECTED_PAGES)
      expect(logger).to have_received(:warn).with(/Stopped paginating/)
    end

    # The thread enriches a page rather than being it: a failure costs the
    # operator the column, not the records they opened.
    it 'degrades to nil and reports the failure when the thread cannot be read' do
      allow(ForestAdminDatasourcePylon).to receive(:logger).and_return(logger)
      stub_request(:get, "#{base}/issues/i1/messages").to_return(json({ 'message' => 'boom' }, 500))

      expect(client.fetch_issue_messages('i1')).to be_nil
      expect(logger).to have_received(:warn).with(/fetch_issue_messages\(i1\) failed; degrading.*HTTP 500 boom/)
    end

    it 'degrades on a missing issue rather than raising a 404' do
      stub_request(:get, "#{base}/issues/nope/messages").to_return(json({ 'message' => 'not found' }, 404))

      expect(client.fetch_issue_messages('nope')).to be_nil
    end
  end

  describe '#search_accounts' do
    it 'posts the full search envelope and returns the records' do
      stub_request(:post, "#{base}/accounts/search").to_return(json('data' => [{ 'id' => 'a1' }]))
      filter = { 'field' => 'name', 'operator' => 'equals', 'values' => ['Acme'] }

      page = client.search_accounts(limit: 2, cursor: 'c1', filter: filter, search_text: 'acme')

      expect(page.records).to eq([{ 'id' => 'a1' }])
      expect(WebMock).to have_requested(:post, "#{base}/accounts/search")
        .with(body: { 'limit' => 2, 'cursor' => 'c1', 'filter' => filter, 'search_text' => 'acme' })
    end

    it 'omits cursor, filter and search_text when they are not provided' do
      stub_request(:post, "#{base}/accounts/search").to_return(json('data' => []))

      client.search_accounts(limit: 5, cursor: nil, filter: nil, search_text: '')

      expect(WebMock).to have_requested(:post, "#{base}/accounts/search").with(body: { 'limit' => 5 })
    end

    it 'wraps a failure in an APIError naming the endpoint' do
      body = { 'message' => 'bad filter', 'request_id' => 'req_7' }
      stub_request(:post, "#{base}/accounts/search").to_return(json(body, 400))

      expect { client.search_accounts(limit: 1) }.to raise_error(ForestAdminDatasourcePylon::APIError) { |error|
        expect(error.status).to eq(400)
        expect(error.message)
          .to eq('Pylon API call failed: accounts/search: HTTP 400 bad filter (request_id: req_7)')
      }
    end
  end

  describe '#search_contacts' do
    it 'posts to the contacts endpoint, clamps the limit and exposes the next cursor' do
      stub_request(:post, "#{base}/contacts/search")
        .to_return(json('data' => [{ 'id' => 'ct1' }], 'pagination' => { 'cursor' => 'c2', 'has_next_page' => true }))

      page = client.search_contacts(limit: 99_999)

      expect(page.records).to eq([{ 'id' => 'ct1' }])
      expect(page.next_cursor).to eq('c2')
      expect(WebMock).to have_requested(:post, "#{base}/contacts/search")
        .with(body: { 'limit' => described_class::MAX_SEARCH_LIMIT })
    end
  end

  describe '#list_accounts' do
    # Unlike POST /accounts/search, the paginated GET rejects a request that
    # does not carry a limit.
    it 'sends the mandatory limit as a query parameter' do
      stub_request(:get, "#{base}/accounts").with(query: { 'limit' => '2' })
                                            .to_return(json('data' => [{ 'id' => 'a1' }]))

      page = client.list_accounts(limit: 2)

      expect(page.records).to eq([{ 'id' => 'a1' }])
      expect(page.next_cursor).to be_nil
    end

    it 'forwards the cursor and clamps the limit' do
      stub_request(:get, "#{base}/accounts").with(query: { 'limit' => '1000', 'cursor' => 'c1' })
                                            .to_return(json('data' => []))

      client.list_accounts(limit: 99_999, cursor: 'c1')

      expect(WebMock).to have_requested(:get, "#{base}/accounts")
        .with(query: { 'limit' => '1000', 'cursor' => 'c1' })
    end

    it 'omits an empty cursor' do
      stub_request(:get, "#{base}/accounts").with(query: { 'limit' => '5' }).to_return(json('data' => []))

      client.list_accounts(limit: 5, cursor: '')

      expect(WebMock).to have_requested(:get, "#{base}/accounts").with(query: { 'limit' => '5' })
    end

    it 'exposes the cursor when a next page is advertised' do
      stub_request(:get, "#{base}/accounts").with(query: { 'limit' => '1' })
                                            .to_return(json('data' => [],
                                                            'pagination' => {
                                                              'cursor' => 'c2', 'has_next_page' => true
                                                            }))

      expect(client.list_accounts(limit: 1).next_cursor).to eq('c2')
    end

    it 'reports no next cursor when has_next_page is false' do
      stub_request(:get, "#{base}/accounts").with(query: { 'limit' => '1' })
                                            .to_return(json('data' => [],
                                                            'pagination' => {
                                                              'cursor' => 'c2', 'has_next_page' => false
                                                            }))

      expect(client.list_accounts(limit: 1).next_cursor).to be_nil
    end

    it 'wraps a failure in an APIError carrying status, body and request_id' do
      body = { 'message' => 'limit is required', 'request_id' => 'req_9' }
      stub_request(:get, "#{base}/accounts").with(query: { 'limit' => '1' }).to_return(json(body, 400))

      expect { client.list_accounts(limit: 1) }.to raise_error(ForestAdminDatasourcePylon::APIError) { |error|
        expect(error.status).to eq(400)
        expect(error.body).to eq(body)
        expect(error.message)
          .to eq('Pylon API call failed: accounts: HTTP 400 limit is required (request_id: req_9)')
      }
    end
  end

  describe '#list_contacts' do
    # The OpenAPI spec omits the query parameters of GET /contacts, but the
    # endpoint paginates exactly like GET /accounts.
    it 'paginates like the accounts listing' do
      stub_request(:get, "#{base}/contacts").with(query: { 'limit' => '2', 'cursor' => 'c1' })
                                            .to_return(json('data' => [{ 'id' => 'ct1' }],
                                                            'pagination' => {
                                                              'cursor' => 'c2', 'has_next_page' => true
                                                            }))

      page = client.list_contacts(limit: 2, cursor: 'c1')

      expect(page.records).to eq([{ 'id' => 'ct1' }])
      expect(page.next_cursor).to eq('c2')
    end
  end

  describe '#fetch_account' do
    it 'unwraps the account' do
      stub_request(:get, "#{base}/accounts/a1").to_return(json('data' => { 'id' => 'a1', 'name' => 'Acme' }))

      expect(client.fetch_account('a1')).to eq('id' => 'a1', 'name' => 'Acme')
    end

    it 'accepts an external id as well as a uuid' do
      stub_request(:get, "#{base}/accounts/ext%2F42").to_return(json('data' => { 'id' => 'a1' }))

      expect(client.fetch_account('ext/42')).to eq('id' => 'a1')
    end

    it 'wraps a missing account in a 404 APIError naming the endpoint' do
      stub_request(:get, "#{base}/accounts/nope").to_return(json({ 'message' => 'not found' }, 404))

      expect { client.fetch_account('nope') }.to raise_error(ForestAdminDatasourcePylon::APIError) { |error|
        expect(error.status).to eq(404)
        expect(error.message).to match(%r{accounts/nope: HTTP 404 not found})
      }
    end
  end

  describe '#fetch_contact' do
    it 'unwraps the contact' do
      stub_request(:get, "#{base}/contacts/ct1").to_return(json('data' => { 'id' => 'ct1', 'email' => 'a@b.c' }))

      expect(client.fetch_contact('ct1')).to eq('id' => 'ct1', 'email' => 'a@b.c')
    end
  end

  describe '#fetch_users' do
    it 'includes deactivated users by default' do
      stub_request(:get, "#{base}/users").with(query: { 'include_deactivated' => 'true' })
                                         .to_return(json('data' => [{ 'id' => 'u1' }, { 'id' => 'u2' }]))

      expect(client.fetch_users).to eq([{ 'id' => 'u1' }, { 'id' => 'u2' }])
    end

    it 'can ask for active users only' do
      stub_request(:get, "#{base}/users").with(query: { 'include_deactivated' => 'false' })
                                         .to_return(json('data' => []))

      client.fetch_users(include_deactivated: false)

      expect(WebMock).to have_requested(:get, "#{base}/users").with(query: { 'include_deactivated' => 'false' })
    end

    it 'returns an empty array when the payload carries no data' do
      stub_request(:get, "#{base}/users").with(query: { 'include_deactivated' => 'true' })
                                         .to_return(json('data' => nil))

      expect(client.fetch_users).to eq([])
    end

    it 'wraps a failure in an APIError naming the endpoint' do
      stub_request(:get, "#{base}/users").with(query: { 'include_deactivated' => 'true' })
                                         .to_return(json({ 'message' => 'boom' }, 500))

      expect { client.fetch_users }
        .to raise_error(ForestAdminDatasourcePylon::APIError, /users: HTTP 500 boom/)
    end
  end

  describe '#fetch_user' do
    it 'unwraps the user' do
      stub_request(:get, "#{base}/users/u1").to_return(json('data' => { 'id' => 'u1', 'name' => 'Ada' }))

      expect(client.fetch_user('u1')).to eq('id' => 'u1', 'name' => 'Ada')
    end
  end

  describe '#fetch_teams' do
    it 'returns every team without sending any query parameter' do
      stub_request(:get, "#{base}/teams").to_return(json('data' => [{ 'id' => 't1' }]))

      expect(client.fetch_teams).to eq([{ 'id' => 't1' }])
      expect(WebMock).to have_requested(:get, "#{base}/teams")
    end
  end

  describe '#fetch_team' do
    it 'unwraps the team' do
      stub_request(:get, "#{base}/teams/t1").to_return(json('data' => { 'id' => 't1', 'name' => 'Support' }))

      expect(client.fetch_team('t1')).to eq('id' => 't1', 'name' => 'Support')
    end
  end

  describe '#fetch_custom_fields' do
    let(:logger) { instance_double(Logger, warn: nil) }

    def definitions(records, cursor: nil)
      body = { 'data' => records }
      body['pagination'] = { 'cursor' => cursor, 'has_next_page' => true } if cursor
      json(body)
    end

    # `object_type` is mandatory: Pylon answers 400 without it, so the schema of
    # each collection is read by its own call.
    it 'asks for the definitions of one object type' do
      stub_request(:get, "#{base}/custom-fields").with(query: { 'object_type' => 'issue' })
                                                 .to_return(definitions([{ 'slug' => 'severity' }]))

      expect(client.fetch_custom_fields('issue')).to eq([{ 'slug' => 'severity' }])
    end

    # The mandatory parameter has to survive the walk: dropped on the second
    # page, it would answer with the fields of another object type or with a 400.
    it 'keeps the object type on every page of the walk' do
      stub_request(:get, "#{base}/custom-fields").with(query: { 'object_type' => 'issue' })
                                                 .to_return(definitions([{ 'slug' => 'severity' }], cursor: 'c1'))
      stub_request(:get, "#{base}/custom-fields").with(query: { 'object_type' => 'issue', 'cursor' => 'c1' })
                                                 .to_return(definitions([{ 'slug' => 'tier' }]))

      expect(client.fetch_custom_fields('issue')).to eq([{ 'slug' => 'severity' }, { 'slug' => 'tier' }])
    end

    it 'returns an empty list when the organization defined no custom field' do
      stub_request(:get, "#{base}/custom-fields").with(query: { 'object_type' => 'account' })
                                                 .to_return(definitions(nil))

      expect(client.fetch_custom_fields('account')).to eq([])
    end

    # Read while the agent boots: the datasource has to come up on its native
    # schema rather than fail to come up at all.
    it 'degrades to an empty list and reports the failure' do
      allow(ForestAdminDatasourcePylon).to receive(:logger).and_return(logger)
      stub_request(:get, "#{base}/custom-fields").with(query: { 'object_type' => 'issue' })
                                                 .to_return(json({ 'message' => 'boom' }, 500))

      expect(client.fetch_custom_fields('issue')).to eq([])
      expect(logger).to have_received(:warn).with(/fetch_custom_fields\(issue\) failed; degrading.*HTTP 500 boom/)
    end

    it 'degrades when the token is not allowed to read the definitions' do
      stub_request(:get, "#{base}/custom-fields").with(query: { 'object_type' => 'issue' })
                                                 .to_return(json({ 'message' => 'forbidden' }, 403))

      expect(client.fetch_custom_fields('issue')).to eq([])
    end
  end

  # The introspection runs while the datasource is being constructed, so it is
  # read through a connection of its own: what the resilient one is willing to
  # wait for is minutes of Rails boot the operator sits through.
  describe 'the boot connection' do
    let(:fast_boot) { ForestAdminDatasourcePylon::RetryPolicy.new(max_retries: 1, interval: 0, max_interval: 2) }
    let(:definitions) { "#{base}/custom-fields" }

    def boot_client(**options)
      described_class.new(ForestAdminDatasourcePylon::Configuration.new(api_key: 'k', **options))
    end

    it 'bounds how long one attempt may take' do
      conn = client.send(:boot_connection)

      expect([conn.options.open_timeout, conn.options.timeout]).to eq([3, 10])
    end

    it 'honours the configured boot timeouts' do
      conn = boot_client(boot_open_timeout: 1, boot_timeout: 2).send(:boot_connection)

      expect([conn.options.open_timeout, conn.options.timeout]).to eq([1, 2])
    end

    # The whole point of the bound: faraday-retry abandons a Retry-After past
    # max_interval, so a rate-limited boot degrades at once instead of waiting
    # out a window per attempt.
    it 'gives up at once on a 429 carrying a whole rate-limit window' do
      stub_request(:get, definitions).with(query: { 'object_type' => 'issue' })
                                     .to_return(status: 429, body: { 'message' => 'slow down' }.to_json,
                                                headers: { 'Content-Type' => 'application/json',
                                                           'Retry-After' => '60' })

      expect(client.fetch_custom_fields('issue')).to eq([])
      expect(WebMock).to have_requested(:get, definitions).with(query: { 'object_type' => 'issue' }).once
    end

    # One retry rather than none: the introspection runs once and is never
    # revisited, so a hiccup would cost the custom columns for the whole life of
    # the process.
    it 'retries once a failure Pylon sent without a Retry-After' do
      stub_request(:get, definitions).with(query: { 'object_type' => 'issue' })
                                     .to_return(json({ 'message' => 'slow down' }, 429))
                                     .then.to_return(json('data' => [{ 'slug' => 'severity' }]))

      expect(boot_client(boot_retry_policy: fast_boot).fetch_custom_fields('issue'))
        .to eq([{ 'slug' => 'severity' }])
      expect(WebMock).to have_requested(:get, definitions).with(query: { 'object_type' => 'issue' }).twice
    end

    it 'spends no more than that one retry' do
      stub_request(:get, definitions).with(query: { 'object_type' => 'issue' })
                                     .to_return(json({ 'message' => 'slow down' }, 429))

      expect(boot_client(boot_retry_policy: fast_boot).fetch_custom_fields('issue')).to eq([])
      expect(WebMock).to have_requested(:get, definitions).with(query: { 'object_type' => 'issue' }).twice
    end

    # Pylon meters the endpoint, so the boot spends the same budget as every
    # later call: a window of its own would spend that budget twice over.
    it 'meters the introspection on the limiter the rest of the client uses' do
      limiter = instance_spy(ForestAdminDatasourcePylon::RateLimiter)
      stub_request(:get, definitions).with(query: { 'object_type' => 'issue' }).to_return(json('data' => []))

      boot_client(rate_limiter: limiter).fetch_custom_fields('issue')
      expect(limiter).to have_received(:acquire).with(:get, '/custom-fields')
    end

    # The other cursor walk is a request the operator is already waiting on, and
    # keeps the patience the resilient policy grants it -- here two retries,
    # where the boot connection would have spent one.
    it 'leaves every other call on the resilient connection' do
      messages = "#{base}/issues/i1/messages"
      stub_request(:get, messages).to_return(json({ 'message' => 'slow down' }, 429))

      expect(client.fetch_issue_messages('i1')).to be_nil
      expect(WebMock).to have_requested(:get, messages).times(3)
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
