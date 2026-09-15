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

      # A body that failed to parse is a payload, not an error: on a 200 it is
      # customer content, and this message is shown in the interface and
      # collected by whatever watches the agent (R10).
      it 'names a body it could not read rather than quoting it' do
        stub_request(:get, "#{base}/me")
          .to_return(json('Bonjour, voici mon RIB FR76 3000 4000 0500 0012 3456 789'))

        expect { client.me }.to raise_error(APIError) { |error|
          expect(error.message).to eq('Intercom API call failed: me: the response could not be read as JSON')
          # Faraday hands a parsing error an unfinished response, so there is no
          # body to keep here -- which suits this one: the point is that the
          # payload does not travel with the error.
          expect(error.body).to be_nil
        }
      end

      # The same guard, one level down: a parser raising on its own would
      # otherwise reach the catch-all, whose message is the exception's -- and
      # a JSON parser quotes what it choked on.
      it 'says as little when a parser raises outside Faraday' do
        stub_request(:get, "#{base}/me").to_raise(JSON::ParserError.new("unexpected token 'mon RIB FR76'"))

        expect { client.me }.to raise_error(APIError) { |error|
          expect(error.message).to include('could not be read as JSON')
          expect(error.message).not_to include('RIB')
        }
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

    # The workspace's own lists, held for the configured window rather than
    # re-read by every page that resolves a relation through one of them.
    describe '#fetch_all caching' do
      before { stub_request(:get, "#{base}/teams").to_return(json('teams' => [{ 'id' => '1' }])) }

      it 'reads the endpoint once within the window' do
        2.times { client.fetch_all('teams', list_key: 'teams') }

        expect(WebMock).to have_requested(:get, "#{base}/teams").once
      end

      it 'answers the second read with the same records' do
        first = client.fetch_all('teams', list_key: 'teams')

        expect(client.fetch_all('teams', list_key: 'teams')).to eq(first)
      end

      # `boot` picks the connection a read travels on -- shorter timeouts while
      # the agent starts -- not what comes back, so the ticket types read at boot
      # are the ticket types a list view reads.
      it 'shares one entry between the boot read and the later one' do
        client.fetch_all('teams', list_key: 'teams', boot: true)
        client.fetch_all('teams', list_key: 'teams')

        expect(WebMock).to have_requested(:get, "#{base}/teams").once
      end

      # `/data_attributes` answers the contact attributes and the company ones
      # under `?model=`, and both are read whole.
      it 'tells two reads of one endpoint apart by their params' do
        stub_request(:get, "#{base}/data_attributes").with(query: hash_including({}))
                                                     .to_return(json('data' => []))

        client.fetch_all('data_attributes', params: { 'model' => 'contact' })
        client.fetch_all('data_attributes', params: { 'model' => 'company' })

        expect(WebMock).to have_requested(:get, "#{base}/data_attributes").with(query: { 'model' => 'contact' })
        expect(WebMock).to have_requested(:get, "#{base}/data_attributes").with(query: { 'model' => 'company' })
      end

      it 'hands back a frozen list, nothing downstream owning what the next page reads' do
        expect(client.fetch_all('teams', list_key: 'teams')).to be_frozen
      end

      # A 403 rather than a 500: the latter is retried, and the retry would eat
      # the answer this example checks is read afresh.
      it 'caches no failure' do
        stub_request(:get, "#{base}/admins").to_return(json({}, 403), json('admins' => [{ 'id' => '1' }]))

        expect { client.fetch_all('admins', list_key: 'admins') }.to raise_error(APIError)
        expect(client.fetch_all('admins', list_key: 'admins').size).to eq(1)
      end

      context 'with the store off' do
        let(:configuration) do
          Configuration.new(access_token: 's3cr3t', retry_policy: retry_policy, rate_limiter: nil,
                            reference_cache_ttl: 0)
        end

        it 'reads the endpoint on every call' do
          2.times { client.fetch_all('teams', list_key: 'teams') }

          expect(WebMock).to have_requested(:get, "#{base}/teams").twice
        end
      end
    end

    # The other half: the same read issued twice while a single page is being
    # built, from two callers that cannot see each other.
    describe '#with_read_scope' do
      before do
        stub_request(:post, "#{base}/contacts/search").to_return(json('data' => [{ 'id' => 'c1' }]))
        stub_request(:get, %r{#{base}/contacts/c1}).to_return(json('id' => 'c1'))
      end

      def search
        client.search_page('contacts/search', query: { 'field' => 'id', 'operator' => 'IN', 'value' => ['c1'] },
                                              per_page: 1)
      end

      it 'issues one request for two identical searches' do
        client.with_read_scope { 2.times { search } }

        expect(WebMock).to have_requested(:post, "#{base}/contacts/search").once
      end

      it 'answers the second search with the first page' do
        pages = client.with_read_scope { [search, search] }

        expect(pages.first.records).to eq(pages.last.records)
      end

      it 'issues one request for two reads of one record' do
        client.with_read_scope { 2.times { client.fetch_record('contacts', 'c1') } }

        expect(WebMock).to have_requested(:get, "#{base}/contacts/c1").once
      end

      it 'tells two searches apart by their query' do
        client.with_read_scope do
          search
          client.search_page('contacts/search', query: { 'field' => 'id', 'operator' => 'IN', 'value' => ['c2'] },
                                                per_page: 1)
        end

        expect(WebMock).to have_requested(:post, "#{base}/contacts/search").twice
      end

      it 'remembers nothing outside a scope' do
        2.times { search }

        expect(WebMock).to have_requested(:post, "#{base}/contacts/search").twice
      end

      # A page is one scope, and the next page is another: what travels here is
      # the customer's own records, and holding them would show an operator a row
      # they have just edited in its previous state.
      it 'remembers nothing from one scope to the next' do
        2.times { client.with_read_scope { search } }

        expect(WebMock).to have_requested(:post, "#{base}/contacts/search").twice
      end

      # A related list resolves relations of its own, and the inner `ensure`
      # would otherwise close the scope the outer read is still building in.
      it 'joins the scope already open rather than opening a second one' do
        client.with_read_scope do
          search
          client.with_read_scope { search }
          search
        end

        expect(WebMock).to have_requested(:post, "#{base}/contacts/search").once
      end

      it 'closes the scope even when the page fails' do
        expect { client.with_read_scope { raise APIError, 'boom' } }.to raise_error(APIError)

        2.times { search }
        expect(WebMock).to have_requested(:post, "#{base}/contacts/search").twice
      end

      it 'remembers no failure' do
        stub_request(:post, "#{base}/companies/search").to_return(json({}, 500), json('data' => []))

        client.with_read_scope do
          expect { client.search_page('companies/search', query: {}, per_page: 1) }.to raise_error(APIError)
          client.search_page('companies/search', query: {}, per_page: 1)
        end

        expect(WebMock).to have_requested(:post, "#{base}/companies/search").twice
      end
    end

    # Seven requests to one host is seven TLS handshakes on the default adapter.
    describe 'connection reuse' do
      it 'builds its connections on the persistent adapter' do
        stub_request(:get, "#{base}/me").to_return(json('type' => 'admin'))
        client.me

        expect(WebMock).to have_requested(:get, "#{base}/me").with(headers: { 'Connection' => 'keep-alive' })
      end

      # An optimisation nothing can load is a warning and a slower request, not
      # a boot that fails.
      it 'falls back to Faraday\'s default when the adapter is not registered, and says so' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        unloadable = described_class.new(
          Configuration.new(access_token: 's3cr3t', rate_limiter: nil, adapter: :no_such_adapter)
        )
        stub_request(:get, "#{base}/me").to_return(json('type' => 'admin'))

        unloadable.me

        expect(WebMock).to have_requested(:get, "#{base}/me")
        expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/adapter is not available/)
      end

      it 'takes the adapter the configuration names' do
        configured = described_class.new(
          Configuration.new(access_token: 's3cr3t', rate_limiter: nil, adapter: :net_http)
        )
        stub_request(:get, "#{base}/me").to_return(json('type' => 'admin'))

        configured.me

        expect(WebMock).to have_requested(:get, "#{base}/me")
      end

      # Faraday looks a name up by symbol, so a string used to fall through to
      # the default adapter -- keep-alive lost, and the warning naming the
      # adapter it fell back to as the one that was unavailable.
      it 'keeps the connection alive for a name spelled as a string' do
        configured = described_class.new(
          Configuration.new(access_token: 's3cr3t', rate_limiter: nil, adapter: 'net_http_persistent')
        )
        stub_request(:get, "#{base}/me").to_return(json('type' => 'admin'))

        configured.me

        expect(WebMock).to have_requested(:get, "#{base}/me").with(headers: { 'Connection' => 'keep-alive' })
      end
    end

    # What a pooled connection costs: a socket the server closed while it was
    # idle fails the next request that reuses it, where a client opening one per
    # request could not meet the case. On a GET the retry policy already
    # absorbed it; the searches every list view is built on travel on POST.
    describe 'a connection dropped under keep-alive' do
      it 'retries a search, which reads despite travelling on POST' do
        stub_request(:post, "#{base}/contacts/search")
          .to_raise(Faraday::ConnectionFailed).then
          .to_return(json('data' => [{ 'id' => 'c1' }]))

        page = client.search_page('contacts/search', query: {}, per_page: 1)

        expect(page.records.size).to eq(1)
        expect(WebMock).to have_requested(:post, "#{base}/contacts/search").twice
      end

      # The other read Intercom answers on POST, and the reason the exemption is
      # scoped to paths rather than to the verb.
      it 'retries the offset listing' do
        stub_request(:post, "#{base}/companies/list").with(query: hash_including({}))
                                                     .to_raise(Faraday::ConnectionFailed).then
                                                     .to_return(json('data' => []))

        expect(client.offset_page('companies/list', page: 1, per_page: 1).records).to eq([])
        expect(WebMock).to have_requested(:post, "#{base}/companies/list")
          .with(query: hash_including({})).twice
      end

      # The persistent adapter re-raises its own error for what it does not
      # recognise -- a host found down while a pooled connection is reset -- so
      # the policy names the class it cannot reference. Required here rather
      # than at the top of the file: nothing guarantees the optional gem is
      # loaded before this example runs.
      it 'retries the adapter error a dropped connection can surface as' do
        require 'net/http/persistent'
        stub_request(:get, "#{base}/me")
          .to_raise(Net::HTTP::Persistent::Error.new('host down: api.intercom.io:443')).then
          .to_return(json('type' => 'admin'))

        client.me

        expect(WebMock).to have_requested(:get, "#{base}/me").twice
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
