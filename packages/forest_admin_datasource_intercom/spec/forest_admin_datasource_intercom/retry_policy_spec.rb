module ForestAdminDatasourceIntercom
  RSpec.describe RetryPolicy do
    describe '#to_faraday_options' do
      subject(:options) { described_class.new.to_faraday_options }

      it 'retries the statuses worth another attempt' do
        expect(options[:retry_statuses]).to eq([429, 500, 502, 503, 504])
      end

      # A 502 on the way back from a POST Intercom did perform would be replayed
      # into a second reply on the conversation.
      it 'only replays the verbs that change nothing' do
        expect(options[:methods]).to eq(%i[get head options])
      end

      it 'replays a 429 whatever the verb, Intercom having rejected it unprocessed' do
        expect(options[:retry_if].call({ status: 429 }, nil)).to be(true)
      end

      it 'leaves any other status to the methods list' do
        expect(options[:retry_if].call({ status: 502 }, nil)).to be(false)
      end

      # faraday-retry abandons outright when Retry-After exceeds max_interval,
      # so the cap has to cover Intercom's whole 10-second window.
      it 'waits out a full rate-limit window' do
        expect(options[:max_interval]).to be > RateLimiter::WINDOW
      end

      it 'absorbs a dropped connection, which faraday-retry does not by default' do
        expect(options[:exceptions]).to include(Faraday::ConnectionFailed)
      end
    end

    describe '.boot' do
      subject(:options) { described_class.boot.to_faraday_options }

      it 'retries once: a boot read is never revisited, and never worth a long wait' do
        expect(options[:max]).to eq(1)
      end

      # Below a rate-limit window on purpose: past the cap faraday-retry gives
      # up at once, which is what keeps a 429 from holding the Rails boot.
      it 'gives up rather than waiting a 429 out' do
        expect(options[:max_interval]).to be < RateLimiter::WINDOW
      end
    end
  end
end
