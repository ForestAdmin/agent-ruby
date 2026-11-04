module ForestAdminDatasourceIntercom
  RSpec.describe Throttle do
    let(:limiter) { instance_double(RateLimiter, acquire: nil, observe: nil) }
    let(:connection) do
      Faraday.new(url: 'https://api.intercom.test') do |f|
        f.use described_class, limiter: limiter
      end
    end

    before do
      stub_request(:get, 'https://api.intercom.test/me')
        .to_return(status: 200, body: '{}',
                   headers: { 'Content-Type' => 'application/json', 'x-ratelimit-remaining' => '7' })
    end

    it 'asks for room before the request leaves' do
      connection.get('me')

      expect(limiter).to have_received(:acquire)
    end

    it 'hands the window back what the response says about it' do
      connection.get('me')

      expect(limiter).to have_received(:observe).with(hash_including('x-ratelimit-remaining' => '7'))
    end

    # The 429 carries the most useful reset of all, so the observation cannot be
    # limited to the responses that succeeded.
    it 'observes a rejected response too' do
      stub_request(:get, 'https://api.intercom.test/me')
        .to_return(status: 429, body: '{}',
                   headers: { 'Content-Type' => 'application/json', 'x-ratelimit-remaining' => '0' })

      connection.get('me')

      expect(limiter).to have_received(:observe).with(hash_including('x-ratelimit-remaining' => '0'))
    end
  end
end
