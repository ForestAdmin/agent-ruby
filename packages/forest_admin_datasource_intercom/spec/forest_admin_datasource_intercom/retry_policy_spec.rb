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

      # The persistent adapter re-raises its own error for the part of its
      # surface it does not translate, and the gem is optional -- so the class
      # is named rather than referenced, and faraday-retry skips a name nothing
      # defined.
      it 'absorbs the adapter error a dropped connection can also surface as' do
        expect(options[:exceptions]).to include('Net::HTTP::Persistent::Error')
      end

      context 'when a pooled connection was dropped' do
        let(:dropped) { Faraday::ConnectionFailed.new('closed') }

        def env(path)
          { status: nil, url: URI.parse("https://api.intercom.io/#{path}") }
        end

        # Keep-alive is what makes this ordinary rather than impossible: a socket
        # the server closed while it was idle fails the next request that reuses
        # it, and every list view of this datasource is built on one of these.
        it 'replays the reads Intercom answers through POST' do
          %w[contacts/search tickets/search conversations/search companies/list].each do |path|
            expect(options[:retry_if].call(env(path), dropped)).to be(true)
          end
        end

        # The guarantee the exemption had to leave intact, and the reason it is
        # scoped to paths rather than to the verb.
        it 'never replays a POST that writes' do
          %w[conversations tickets contacts conversations/123/reply].each do |path|
            expect(options[:retry_if].call(env(path), dropped)).to be(false)
          end
        end

        it 'leaves a GET to the methods list, which already replays it' do
          expect(options[:retry_if].call(env('me'), dropped)).to be(false)
          expect(options[:methods]).to include(:get)
        end
      end
    end

    describe '.connection_failure?' do
      it "knows Faraday's own" do
        expect(described_class).to be_connection_failure(Faraday::ConnectionFailed.new('closed'))
      end

      # Raised when resetting a pooled connection finds the host down, and it
      # reaches Faraday unwrapped: the adapter translates the messages it
      # recognises -- a timeout, a refused connection -- and re-raises the rest.
      it "knows the persistent adapter's, which it cannot name outright" do
        require 'net/http/persistent'

        expect(described_class).to be_connection_failure(Net::HTTP::Persistent::Error.new('host down'))
      end

      it 'takes nothing else for one' do
        expect(described_class).not_to be_connection_failure(Faraday::TimeoutError.new('slow'))
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
