RSpec.describe ForestAdminDatasourcePylon::Client::Writes do
  let(:retry_policy) { ForestAdminDatasourcePylon::RetryPolicy.new(max_retries: 2, interval: 0) }
  let(:configuration) { ForestAdminDatasourcePylon::Configuration.new(api_key: 'k', retry_policy: retry_policy) }
  let(:client) { ForestAdminDatasourcePylon::Client.new(configuration) }
  let(:base) { configuration.url }

  def json(payload, status = 200)
    { status: status, body: payload.is_a?(String) ? payload : payload.to_json,
      headers: { 'Content-Type' => 'application/json' } }
  end

  # One method per endpoint, and the endpoint is the whole of what each one
  # knows: the payload is the collection's to build.
  describe 'the endpoint each write reaches' do
    {
      create_issue: [:post, 'issues'], create_account: [:post, 'accounts'],
      create_contact: [:post, 'contacts'], create_team: [:post, 'teams']
    }.each do |method, (verb, path)|
      it "#{method} posts to /#{path}" do
        stub_request(verb, "#{base}/#{path}").to_return(json('data' => { 'id' => 'x' }))

        expect(client.public_send(method, 'name' => 'Acme')).to eq('id' => 'x')
        expect(WebMock).to have_requested(verb, "#{base}/#{path}").with(body: { 'name' => 'Acme' })
      end
    end

    {
      update_issue: 'issues', update_account: 'accounts', update_contact: 'contacts',
      update_team: 'teams', update_user: 'users'
    }.each do |method, path|
      it "#{method} patches /#{path}/{id}" do
        stub_request(:patch, "#{base}/#{path}/x1").to_return(json('data' => { 'id' => 'x1' }))

        expect(client.public_send(method, 'x1', 'name' => 'Acme')).to eq('id' => 'x1')
        expect(WebMock).to have_requested(:patch, "#{base}/#{path}/x1").with(body: { 'name' => 'Acme' })
      end
    end

    { delete_issue: 'issues', delete_account: 'accounts', delete_contact: 'contacts' }.each do |method, path|
      it "#{method} deletes /#{path}/{id}" do
        stub_request(:delete, "#{base}/#{path}/x1").to_return(status: 204)

        expect(client.public_send(method, 'x1')).to be(true)
        expect(WebMock).to have_requested(:delete, "#{base}/#{path}/x1")
      end
    end
  end

  describe 'the record a write answers with' do
    it 'unwraps the "data" envelope' do
      stub_request(:post, "#{base}/issues")
        .to_return(json('data' => { 'id' => 'i1', 'title' => 'Boom' }, 'request_id' => 'req_1'))

      expect(client.create_issue('title' => 'Boom')).to eq('id' => 'i1', 'title' => 'Boom')
    end

    # A read hands an unwrapped body back untouched; a write must not, or the
    # collection would serialize an envelope into a record carrying no id.
    it 'raises when the envelope carries no record' do
      stub_request(:post, "#{base}/issues").to_return(json('request_id' => 'req_1'))

      expect { client.create_issue('title' => 'Boom') }
        .to raise_error(ForestAdminDatasourcePylon::APIError, /create\(issues\).*unexpected body shape/m)
    end

    it 'raises when the record is not an object' do
      stub_request(:patch, "#{base}/issues/i1").to_return(json('data' => 'ok'))

      expect { client.update_issue('i1', 'title' => 'Boom') }
        .to raise_error(ForestAdminDatasourcePylon::APIError, %r{update\(issues/i1\)})
    end

    # An update's record is discarded by the collection, so an answer carrying
    # none is the write having landed with nothing to hand back — raising there
    # would report a failure on a record Pylon already patched.
    it 'accepts an update answered with no body at all' do
      stub_request(:patch, "#{base}/issues/i1").to_return(status: 204)

      expect(client.update_issue('i1', 'title' => 'Boom')).to be_nil
    end

    it 'accepts an update answered without a record' do
      stub_request(:patch, "#{base}/issues/i1").to_return(json('data' => nil, 'request_id' => 'req_1'))
      stub_request(:patch, "#{base}/issues/i2").to_return(json('request_id' => 'req_2'))

      expect(client.update_issue('i1', 'title' => 'Boom')).to be_nil
      expect(client.update_issue('i2', 'title' => 'Boom')).to be_nil
    end
  end

  describe 'a failed write' do
    it 'raises an APIError carrying the status and the request id' do
      stub_request(:post, "#{base}/issues")
        .to_return(json({ 'message' => 'title is required', 'request_id' => 'req_9' }, 422))

      expect { client.create_issue({}) }.to raise_error(ForestAdminDatasourcePylon::APIError) { |error|
        expect(error.status).to eq(422)
        expect(error.message).to include('create(issues)', 'HTTP 422', 'title is required', 'req_9')
      }
    end

    it 'names the deleted record in the operation' do
      stub_request(:delete, "#{base}/issues/i1").to_return(json({ 'message' => 'gone' }, 404))

      expect { client.delete_issue('i1') }
        .to raise_error(ForestAdminDatasourcePylon::APIError, %r{delete\(issues/i1\)})
    end

    # Ids reach the client from a filter the operator set, so they are escaped
    # rather than joined to the path as they come.
    it 'escapes an id that would otherwise alter the request path' do
      stub_request(:patch, "#{base}/issues/a%2Fb").to_return(json('data' => { 'id' => 'a/b' }))

      client.update_issue('a/b', 'title' => 'Boom')

      expect(WebMock).to have_requested(:patch, "#{base}/issues/a%2Fb")
    end
  end

  # A 429 is refused before Pylon processes the request, so replaying it creates
  # nothing twice; a 502 may well have created the issue, and is not replayed.
  describe 'retrying a write' do
    it 'retries a rate-limited create' do
      stub_request(:post, "#{base}/issues")
        .to_return(json({ 'message' => 'slow down' }, 429))
        .then.to_return(json('data' => { 'id' => 'i1' }))

      expect(client.create_issue('title' => 'Boom')).to eq('id' => 'i1')
      expect(WebMock).to have_requested(:post, "#{base}/issues").twice
    end

    it 'does not retry a create that failed on a gateway error' do
      stub_request(:post, "#{base}/issues").to_return(json({ 'message' => 'bad gateway' }, 502))

      expect { client.create_issue('title' => 'Boom') }.to raise_error(ForestAdminDatasourcePylon::APIError)
      expect(WebMock).to have_requested(:post, "#{base}/issues").once
    end

    it 'retries a rate-limited delete' do
      stub_request(:delete, "#{base}/issues/i1")
        .to_return(json({ 'message' => 'slow down' }, 429))
        .then.to_return(json({}, 204))

      expect(client.delete_issue('i1')).to be(true)
      expect(WebMock).to have_requested(:delete, "#{base}/issues/i1").twice
    end

    # A 502 on the way back from a DELETE Pylon did perform would be replayed
    # into a 404, which the write path surfaces as a deletion that failed when
    # it landed -- a report of something that did not happen. So the gateway
    # error stays what it is, on a delete as on a create.
    it 'does not retry a delete that failed on a gateway error' do
      stub_request(:delete, "#{base}/issues/i1").to_return(json({ 'message' => 'bad gateway' }, 502))

      expect { client.delete_issue('i1') }.to raise_error(ForestAdminDatasourcePylon::APIError, /502/)
      expect(WebMock).to have_requested(:delete, "#{base}/issues/i1").once
    end
  end
end
