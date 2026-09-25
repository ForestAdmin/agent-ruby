module ForestAdminDatasourceIntercom
  RSpec.describe RateLimiter do
    # Sleeping moves the clock, the way it does outside a spec: a window waited
    # out is a window that has refilled by the time the next request asks.
    subject(:limiter) { build_limiter }

    let(:time) { [1_000.0] }
    let(:slept) { [] }

    def build_limiter(**options)
      sleeper = lambda do |seconds|
        slept << seconds
        time[0] += seconds
      end

      described_class.new(now: -> { time[0] }, sleeper: sleeper, **options)
    end

    # What Intercom answers with: the limit of the 10-second window, what is
    # left of it, and the epoch second it refills at.
    def headers(remaining:, reset_in: 4, limit: 1667)
      { 'x-ratelimit-limit' => limit.to_s,
        'x-ratelimit-remaining' => remaining.to_s,
        'x-ratelimit-reset' => (time[0] + reset_in).to_i.to_s }
    end

    it 'lets the first request through: the budget is what that request discovers' do
      limiter.acquire

      expect(slept).to be_empty
    end

    it 'lets a request through while the window still has room' do
      limiter.observe(headers(remaining: 5))
      limiter.acquire

      expect(slept).to be_empty
    end

    it 'waits for the reset once the window is spent' do
      limiter.observe(headers(remaining: 0, reset_in: 4))
      limiter.acquire

      expect(slept).to eq([4.0])
    end

    it 'lets requests through again once the reset has passed' do
      limiter.observe(headers(remaining: 0, reset_in: -1))
      limiter.acquire

      expect(slept).to be_empty
    end

    # Several requests can be in flight before any of them answers, and a
    # `remaining` that only moves on a response lets all of them through on the
    # same stale figure.
    it 'counts its own requests down rather than trusting the last response' do
      limiter.observe(headers(remaining: 2, reset_in: 3))
      3.times { limiter.acquire }

      expect(slept).to eq([3.0])
    end

    it 'ignores a response from a window older than the one it knows' do
      limiter.observe(headers(remaining: 0, reset_in: 5))
      limiter.observe(headers(remaining: 100, reset_in: -10))
      limiter.acquire

      expect(slept).to eq([5.0])
    end

    it 'adopts a new window whole, generous remaining included' do
      limiter.observe(headers(remaining: 0, reset_in: 2))
      limiter.observe(headers(remaining: 50, reset_in: 12))
      limiter.acquire

      expect(slept).to be_empty
    end

    # A response that left Intercom before the requests now in flight were made
    # must not hand their budget back.
    it 'keeps the smaller remaining inside one window' do
      limiter.observe(headers(remaining: 2, reset_in: 3))
      limiter.acquire
      limiter.observe(headers(remaining: 99, reset_in: 3))
      2.times { limiter.acquire }

      expect(slept).to eq([3.0])
    end

    it 'reads the headers whatever their case' do
      limiter.observe('X-RateLimit-Remaining' => '0', 'X-RateLimit-Reset' => (time[0] + 6).to_i.to_s)
      limiter.acquire

      expect(slept).to eq([6.0])
    end

    it 'ignores a response carrying no rate-limit headers at all' do
      limiter.observe('content-type' => 'application/json')
      limiter.acquire

      expect(slept).to be_empty
    end

    it 'ignores a remaining that is not a number' do
      limiter.observe('x-ratelimit-remaining' => 'many', 'x-ratelimit-reset' => (time[0] + 3).to_i.to_s)
      limiter.acquire

      expect(slept).to be_empty
    end

    it 'sleeps a reset out when it fits within the bound it was given' do
      capped = build_limiter(max_wait: 2.0)
      capped.observe(headers(remaining: 0, reset_in: 1))
      capped.acquire

      expect(slept).to eq([1.0])
    end

    describe 'a reset further out than one window' do
      # Intercom's reset is a timestamp from its clock. One that far out is the
      # two clocks disagreeing, not a window emptying, so the request goes
      # through and the log says why -- waiting an hour would read as a hang.
      before do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        limiter.observe(headers(remaining: 0, reset_in: 3_600))
      end

      it 'lets the request through instead of waiting it out' do
        limiter.acquire

        expect(slept).to be_empty
      end

      it 'says so once, not once per request' do
        3.times { limiter.acquire }

        expect(ForestAdminDatasourceIntercom.logger)
          .to have_received(:warn).once.with(/rate-limit window is spent.*limit 1667/m)
      end
    end

    it 'sleeps for real when handed no sleeper' do
      real = described_class.new(now: -> { 999.96 })
      real.observe('x-ratelimit-remaining' => '0', 'x-ratelimit-reset' => '1000')

      expect { real.acquire }.not_to raise_error
    end
  end
end
