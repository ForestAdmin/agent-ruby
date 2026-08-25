RSpec.describe ForestAdminDatasourcePylon::Throttle do
  let(:limiter) { instance_double(ForestAdminDatasourcePylon::RateLimiter, acquire: nil) }
  let(:retry_policy) { ForestAdminDatasourcePylon::RetryPolicy.new(max_retries: 2, interval: 0) }
  let(:configuration) do
    ForestAdminDatasourcePylon::Configuration.new(api_key: 'k', retry_policy: retry_policy, rate_limiter: limiter)
  end
  let(:client) { ForestAdminDatasourcePylon::Client.new(configuration) }
  let(:base) { configuration.url }

  def json(payload, status = 200)
    { status: status, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  it 'asks for a slot before the request goes out' do
    stub_request(:get, "#{base}/me").to_return(json('data' => { 'id' => 'org_1' }))

    client.me

    expect(limiter).to have_received(:acquire).with(:get, '/me').once
  end

  it 'hands over the path rather than the whole url, which is what the table matches' do
    stub_request(:get, "#{base}/issues/abc-123/messages").to_return(json('data' => []))

    client.fetch_issue_messages('abc-123')

    expect(limiter).to have_received(:acquire).with(:get, '/issues/abc-123/messages')
  end

  it 'meters a search under its own verb' do
    stub_request(:post, "#{base}/issues/search").to_return(json('data' => []))

    client.search_issues(limit: 10)

    expect(limiter).to have_received(:acquire).with(:post, '/issues/search')
  end

  # The whole point of sitting inside `retry` rather than outside it: a replay
  # spends the budget a first attempt did, so it has to wait for a slot too.
  # Outside, this would run once for a request that reached Pylon twice.
  it 'asks for a slot on every attempt, replays included' do
    stub_request(:get, "#{base}/me")
      .to_return(json({ 'message' => 'slow down' }, 429))
      .then.to_return(json('data' => { 'id' => 'org_1' }))

    client.me

    expect(WebMock).to have_requested(:get, "#{base}/me").twice
    expect(limiter).to have_received(:acquire).twice
  end

  describe 'when the configuration declines a limiter' do
    let(:configuration) do
      ForestAdminDatasourcePylon::Configuration.new(api_key: 'k', retry_policy: retry_policy, rate_limiter: nil)
    end

    it 'leaves the throttle out of the stack' do
      stub_request(:get, "#{base}/me").to_return(json('data' => { 'id' => 'org_1' }))

      expect(client.me).to eq('id' => 'org_1')
      expect(limiter).not_to have_received(:acquire)
    end
  end
end
