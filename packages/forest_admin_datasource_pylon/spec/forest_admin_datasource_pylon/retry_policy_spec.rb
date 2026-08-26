RSpec.describe ForestAdminDatasourcePylon::RetryPolicy do
  describe '#initialize' do
    it 'defaults the retry budget' do
      policy = described_class.new
      expect([policy.max_retries, policy.interval, policy.max_interval])
        .to eq([3, 0.5, described_class::DEFAULT_MAX_INTERVAL])
    end

    it 'keeps overridden values' do
      policy = described_class.new(max_retries: 5, interval: 0.1, max_interval: 2)
      expect([policy.max_retries, policy.interval, policy.max_interval]).to eq([5, 0.1, 2])
    end
  end

  describe 'DEFAULT_MAX_INTERVAL' do
    # faraday-retry gives up outright when Retry-After exceeds max_interval, and
    # Pylon quotas are per-minute, so a cap below 60s silently disables the 429
    # retry on exactly the throttled endpoints it exists for.
    it 'covers a full Pylon rate-limit window' do
      expect(described_class::DEFAULT_MAX_INTERVAL).to be >= 60
    end
  end

  describe '.boot' do
    it 'retries once' do
      expect(described_class.boot.max_retries).to eq(1)
    end

    # The mirror image of DEFAULT_MAX_INTERVAL: faraday-retry abandons when
    # Retry-After exceeds the cap, which is how a 429 costs a boot nothing.
    it 'caps the wait below a Pylon rate-limit window' do
      expect(described_class.boot.max_interval).to be < 60
    end

    it 'still absorbs a hiccup Pylon answered without a Retry-After' do
      expect(described_class.boot.interval).to be_positive
    end
  end

  describe '#to_faraday_options' do
    subject(:options) { described_class.new(max_retries: 2, interval: 0.1, max_interval: 7).to_faraday_options }

    it 'maps the budget onto faraday-retry keys' do
      expect(options).to include(max: 2, interval: 0.1, max_interval: 7, backoff_factor: 2)
    end

    it 'retries the throttling and transient-gateway statuses' do
      expect(options[:retry_statuses]).to eq([429, 502, 503, 504])
    end

    it 'retries dropped connections on top of faraday-retry defaults' do
      expect(options[:exceptions]).to include(Faraday::ConnectionFailed, Faraday::RetriableResponse)
    end

    it 'limits blanket retries to the verbs that read' do
      expect(options[:methods]).to eq(%i[get head options])
      expect(options[:methods]).not_to include(:post, :patch)
    end

    # A 502 on the way back from a DELETE Pylon did perform would be replayed
    # into a 404, which the write path surfaces as a deletion that failed when
    # it landed. Only its 429 is retried, through RETRY_IF.
    it 'never replays a delete on anything but a 429' do
      expect(options[:methods]).not_to include(:delete)
    end
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
