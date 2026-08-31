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

    describe '#list_page' do
      def list_body(data, next_page: nil, total: 2)
        body = { 'type' => 'list', 'data' => data, 'total_count' => total,
                 'pages' => { 'type' => 'pages', 'page' => 1, 'per_page' => 50 } }
        body['pages']['next'] = next_page unless next_page.nil?
        body
      end

      it 'reads the records, the next cursor and the exact count off one response' do
        body = list_body([{ 'id' => '1' }], next_page: { 'starting_after' => 'cursor_2' })
        stub_request(:get, "#{base}/conversations").with(query: { 'per_page' => '150' }).to_return(json(body))

        page = client.list_page('conversations', per_page: 150)

        expect(page.records).to eq([{ 'id' => '1' }])
        expect(page.next_cursor).to eq('cursor_2')
        expect(page.total_count).to eq(2)
      end

      it 'sends the cursor the previous page advertised' do
        stub_request(:get, "#{base}/conversations")
          .with(query: { 'per_page' => '50', 'starting_after' => 'cursor_2' })
          .to_return(json(list_body([])))

        client.list_page('conversations', per_page: 50, starting_after: 'cursor_2')

        expect(WebMock).to have_requested(:get, "#{base}/conversations")
          .with(query: { 'per_page' => '50', 'starting_after' => 'cursor_2' })
      end

      it 'bounds the page size before sending it, Intercom refusing rather than clamping' do
        stub_request(:get, "#{base}/conversations").with(query: { 'per_page' => '150' })
                                                   .to_return(json(list_body([])))

        client.list_page('conversations', per_page: 500)

        expect(WebMock).to have_requested(:get, "#{base}/conversations").with(query: { 'per_page' => '150' })
      end

      it 'carries the parameters an endpoint of its own needs' do
        stub_request(:get, "#{base}/conversations")
          .with(query: { 'per_page' => '150', 'display_as' => 'plaintext' }).to_return(json(list_body([])))

        client.list_page('conversations', per_page: 150, params: { 'display_as' => 'plaintext' })

        expect(WebMock).to have_requested(:get, "#{base}/conversations")
          .with(query: hash_including('display_as' => 'plaintext'))
      end

      # The last page simply carries no `pages.next`, which is what stops a walk.
      it 'reports no next cursor on the last page' do
        stub_request(:get, "#{base}/conversations").with(query: hash_including({}))
                                                   .to_return(json(list_body([{ 'id' => '1' }])))

        expect(client.list_page('conversations', per_page: 150).next_cursor).to be_nil
      end

      # An older API version spells `pages.next` as a url, and one can be served
      # despite the pin -- reading the cursor out of it beats taking the page for
      # the last one and truncating the answer.
      it 'reads the cursor out of a next page spelled as a url' do
        url = "#{base}/conversations?per_page=50&starting_after=cursor_9"
        stub_request(:get, "#{base}/conversations").with(query: hash_including({}))
                                                   .to_return(json(list_body([], next_page: url)))

        expect(client.list_page('conversations', per_page: 50).next_cursor).to eq('cursor_9')
      end

      # An advertised page taken for the last one is a silently truncated
      # answer, so every unreadable shape is refused rather than dropped.
      it 'refuses a next-page url carrying no cursor' do
        body = list_body([], next_page: "#{base}/conversations?per_page=50")
        stub_request(:get, "#{base}/conversations").with(query: hash_including({})).to_return(json(body))

        expect { client.list_page('conversations', per_page: 50) }
          .to raise_error(APIError, /pages\.next' carries no cursor/)
      end

      it 'refuses a next-page url it cannot parse' do
        stub_request(:get, "#{base}/conversations").with(query: hash_including({}))
                                                   .to_return(json(list_body([], next_page: 'http://[bad')))

        expect { client.list_page('conversations', per_page: 50) }
          .to raise_error(APIError, /pages\.next' carries no cursor/)
      end

      it 'refuses a next page it can read neither way, rather than truncating silently' do
        stub_request(:get, "#{base}/conversations").with(query: hash_including({}))
                                                   .to_return(json(list_body([], next_page: 42)))

        expect { client.list_page('conversations', per_page: 50) }
          .to raise_error(APIError, /unexpected response shape.*pages\.next/m)
      end

      # `Array()` on the envelope would hand the collection rows built out of
      # [key, value] pairs: a page that looks answered and holds nothing.
      it 'refuses a response whose data is not a list' do
        stub_request(:get, "#{base}/conversations").with(query: hash_including({}))
                                                   .to_return(json({ 'type' => 'list', 'data' => { 'id' => '1' } }))

        expect { client.list_page('conversations', per_page: 50) }
          .to raise_error(APIError, /unexpected response shape.*'data' is not a list/m)
      end

      it 'refuses a response carrying no data at all' do
        stub_request(:get, "#{base}/conversations").with(query: hash_including({}))
                                                   .to_return(json({ 'type' => 'list', 'total_count' => 0 }))

        expect { client.list_page('conversations', per_page: 50) }.to raise_error(APIError, /'data' is not a list/)
      end

      it 'serves an empty page as an empty page, zero being an answer' do
        stub_request(:get, "#{base}/conversations").with(query: hash_including({}))
                                                   .to_return(json(list_body([], total: 0)))

        expect(client.list_page('conversations', per_page: 50))
          .to have_attributes(records: [], next_cursor: nil, total_count: 0)
      end

      # nil rather than 0: zero is an answer, and this is the absence of one.
      it 'reports no count when Intercom sends none' do
        stub_request(:get, "#{base}/conversations").with(query: hash_including({}))
                                                   .to_return(json({ 'type' => 'list', 'data' => [] }))

        expect(client.list_page('conversations', per_page: 50).total_count).to be_nil
      end

      it 'reads a page through the boot connection when asked to' do
        stub_request(:get, "#{base}/ticket_types").with(query: hash_including({}))
                                                  .to_return(json(list_body([{ 'id' => '1' }])))

        expect(client.list_page('ticket_types', per_page: 50, boot: true).records.size).to eq(1)
      end

      it 'names the endpoint when the read fails' do
        stub_request(:get, "#{base}/conversations").with(query: hash_including({}))
                                                   .to_return(json({ 'errors' => [{ 'code' => 'not_found' }] }, 404))

        expect { client.list_page('conversations', per_page: 50) }
          .to raise_error(APIError, /conversations: HTTP 404 not_found/)
      end
    end

    describe '#fetch_all' do
      it 'reads the records under the key the endpoint uses' do
        stub_request(:get, "#{base}/admins")
          .to_return(json('type' => 'admin.list', 'admins' => [{ 'id' => '1' }, { 'id' => '2' }]))

        expect(client.fetch_all('admins', list_key: 'admins').size).to eq(2)
      end

      # Intercom is not consistent about it: /admins and /teams use their own
      # key, /ticket_types the `data` envelope every paginated listing uses.
      it 'falls back to the data envelope' do
        stub_request(:get, "#{base}/ticket_types").to_return(json('type' => 'list', 'data' => [{ 'id' => '1' }]))

        expect(client.fetch_all('ticket_types')).to eq([{ 'id' => '1' }])
      end

      it 'asks for no page: these endpoints answer whole' do
        stub_request(:get, "#{base}/teams").to_return(json('teams' => []))

        client.fetch_all('teams', list_key: 'teams')

        expect(WebMock).to have_requested(:get, "#{base}/teams").with(query: {})
      end

      # A reference collection read as empty is a state column with no values and
      # an assignee shown as a raw id -- worse than a failure naming the shape.
      it 'refuses a response holding neither key' do
        stub_request(:get, "#{base}/admins").to_return(json('type' => 'admin.list', 'admins' => { 'id' => '1' }))

        expect { client.fetch_all('admins', list_key: 'admins') }
          .to raise_error(APIError, /neither 'admins' nor 'data' is a list/)
      end

      it 'reads an empty body as no record' do
        stub_request(:get, "#{base}/admins").to_return(status: 200, body: '')

        expect(client.fetch_all('admins', list_key: 'admins')).to eq([])
      end

      # No pagination parameter in the specification is not a promise that a
      # large workspace answers in one response, and a truncated reference
      # collection would show an operator a state list missing its last states.
      it 'follows a cursor if one is advertised anyway' do
        stub_request(:get, "#{base}/tags").with(query: {})
                                          .to_return(json('data' => [{ 'id' => '1' }],
                                                          'pages' => { 'next' => { 'starting_after' => 'c2' } }))
        stub_request(:get, "#{base}/tags").with(query: { 'starting_after' => 'c2' })
                                          .to_return(json('data' => [{ 'id' => '2' }]))

        expect(client.fetch_all('tags').map { |tag| tag['id'] }).to eq(%w[1 2])
      end

      it 'stops at its page cap and says what it left out' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_request(:get, "#{base}/tags").with(query: hash_including({}))
                                          .to_return(json('data' => [{ 'id' => '1' }],
                                                          'pages' => { 'next' => { 'starting_after' => 'c' } }))

        client.fetch_all('tags')

        expect(WebMock).to have_requested(:get, "#{base}/tags")
          .with(query: hash_including({})).times(described_class::MAX_COLLECTED_PAGES)
        expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/Stopped reading tags/)
      end

      it 'reads through the boot connection when asked to' do
        stub_request(:get, "#{base}/ticket_types").to_return(json('data' => []))

        expect(client.fetch_all('ticket_types', boot: true)).to eq([])
      end

      it 'names the endpoint when the read fails' do
        stub_request(:get, "#{base}/admins").to_return(json({ 'errors' => [{ 'code' => 'forbidden' }] }, 403))

        expect { client.fetch_all('admins', list_key: 'admins') }
          .to raise_error(APIError, /admins: HTTP 403 forbidden/)
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
