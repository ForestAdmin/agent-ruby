RSpec.describe ForestAdminDatasourcePylon::RateLimiter do
  # A window of 6s rather than a minute, and a budget of 2 rather than 120, so a
  # spec can saturate an endpoint in three lines and read the arithmetic off it.
  let(:limit) { 2 }
  let(:limits) do
    rule = ForestAdminDatasourcePylon::RateLimits::Rule.new(name: 'get /things', limit: limit)
    class_double(ForestAdminDatasourcePylon::RateLimits, for: rule)
  end

  let(:now) { [0.0] }
  let(:slept) { [] }

  def limiter(max_wait: 5.0, window: 6.0, rules: limits)
    described_class.new(limits: rules, window: window, max_wait: max_wait,
                        clock: -> { now.first }, sleeper: ->(seconds) { slept << seconds })
  end

  def at(time)
    now[0] = time
  end

  describe '#acquire' do
    it 'lets a request through while the window has room' do
      subject = limiter
      limit.times { subject.acquire(:get, '/things') }

      expect(slept).to be_empty
    end

    # The window is full from t=0 to t=6, so the request asking at t=3 waits the
    # 3s left of it rather than a fresh window.
    it 'waits out what is left of the window when it is full' do
      subject = limiter
      subject.acquire(:get, '/things')
      at(2.0)
      subject.acquire(:get, '/things')

      at(3.0)
      subject.acquire(:get, '/things')

      expect(slept).to eq([3.0])
    end

    # Two callers arriving on a full window take the two slots that free next,
    # not the same one: a limiter handing both the first free slot would let them
    # through together and spend twice the budget at that instant.
    it 'spreads concurrent callers over distinct slots' do
      subject = limiter
      subject.acquire(:get, '/things')
      at(2.0)
      subject.acquire(:get, '/things')

      at(3.0)
      subject.acquire(:get, '/things')
      subject.acquire(:get, '/things')

      expect(slept).to eq([3.0, 5.0])
    end

    it 'lets a request through again once the window has rolled past' do
      subject = limiter
      limit.times { subject.acquire(:get, '/things') }

      at(7.0)
      subject.acquire(:get, '/things')

      expect(slept).to be_empty
    end

    describe 'when the wait would exceed max_wait' do
      it 'lets the request through rather than queueing behind the window' do
        subject = limiter(max_wait: 1.0)
        limit.times { subject.acquire(:get, '/things') }

        subject.acquire(:get, '/things')

        expect(slept).to be_empty
      end

      it 'warns, naming the endpoint and the budget it is at' do
        allow(ForestAdminDatasourcePylon.logger).to receive(:warn)
        subject = limiter(max_wait: 1.0)
        limit.times { subject.acquire(:get, '/things') }

        subject.acquire(:get, '/things')

        expect(ForestAdminDatasourcePylon.logger)
          .to have_received(:warn).with(%r{get /things is at its budget of 2 requests per 6s})
      end

      # The slot it declined to wait for must not be booked: recording it would
      # meter a request nobody made and push every later slot further out, so one
      # burst past the bound would keep the window saturated indefinitely.
      it 'books the slot it takes, not the one it refused' do
        subject = limiter(max_wait: 1.0)
        limit.times { subject.acquire(:get, '/things') }
        subject.acquire(:get, '/things')

        at(7.0)
        subject.acquire(:get, '/things')

        expect(slept).to be_empty
      end
    end

    describe 'across endpoints' do
      let(:limits) do
        class_double(ForestAdminDatasourcePylon::RateLimits).tap do |stub|
          allow(stub).to receive(:for) do |_method, path|
            ForestAdminDatasourcePylon::RateLimits::Rule.new(name: path, limit: limit)
          end
        end
      end

      # Pylon meters each endpoint on its own, so saturating one is no reason to
      # hold back a request to another.
      it 'meters each endpoint on its own window' do
        subject = limiter
        limit.times { subject.acquire(:get, '/things') }

        subject.acquire(:get, '/others')

        expect(slept).to be_empty
      end
    end
  end

  describe 'defaults' do
    it 'meters over a minute, which is the unit Pylon documents' do
      expect(described_class::WINDOW).to eq(60.0)
    end

    # A bound above the Retry-After of a 429 would make the throttle the slower
    # of the two paths it exists to shortcut.
    it 'bounds the wait well under a full rate-limit window' do
      expect(described_class::DEFAULT_MAX_WAIT).to be < described_class::WINDOW
    end

    it 'reads the documented table unless handed another' do
      subject = described_class.new(sleeper: ->(seconds) { slept << seconds })
      expect(subject.max_wait).to eq(described_class::DEFAULT_MAX_WAIT)
      expect(subject.window).to eq(described_class::WINDOW)
    end
  end
end
