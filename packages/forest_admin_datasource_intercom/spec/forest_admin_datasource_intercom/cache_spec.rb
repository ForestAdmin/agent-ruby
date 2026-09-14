module ForestAdminDatasourceIntercom
  RSpec.describe Cache do
    subject(:cache) { described_class.new(ttl: 60, now: -> { clock[:seconds] }) }

    # A clock the examples move by hand: the store measures an elapsed span, and
    # a spec that slept through one would be a spec nobody runs.
    let(:clock) { { seconds: 1_000.0 } }

    it 'reads through on the first miss' do
      expect(cache.fetch('key') { 'answer' }).to eq('answer')
    end

    it 'answers the second read from the store' do
      cache.fetch('key') { 'first' }

      expect(cache.fetch('key') { 'second' }).to eq('first')
    end

    it 'tells two keys apart' do
      cache.fetch('a') { 'first' }

      expect(cache.fetch('b') { 'second' }).to eq('second')
    end

    it 'holds an entry for the whole window' do
      cache.fetch('key') { 'first' }
      clock[:seconds] += 59

      expect(cache.fetch('key') { 'second' }).to eq('first')
    end

    it 'reads the source again once the window has passed' do
      cache.fetch('key') { 'first' }
      clock[:seconds] += 61

      expect(cache.fetch('key') { 'second' }).to eq('second')
    end

    # A failure is not an answer: caching one would keep an outage alive for the
    # length of the window.
    it 'stores nothing when the block raises' do
      expect { cache.fetch('key') { raise APIError, 'boom' } }.to raise_error(APIError)

      expect(cache.fetch('key') { 'answer' }).to eq('answer')
    end

    it 'stores a nil answer rather than reading through it again' do
      nothing = nil
      cache.fetch('key') { nothing }

      expect(cache.fetch('key') { 'second' }).to be_nil
    end

    it 'forgets everything on clear' do
      cache.fetch('key') { 'first' }
      cache.clear

      expect(cache.fetch('key') { 'second' }).to eq('second')
    end

    # Expired entries are dropped on the way past rather than by a sweeper, so
    # a store written to for hours does not grow by one entry per window.
    it 'drops expired entries as it writes' do
      cache.fetch('a') { 'first' }
      clock[:seconds] += 61
      cache.fetch('b') { 'second' }

      expect(cache.instance_variable_get(:@entries).keys).to eq(['b'])
    end

    # The escape hatch a deployment sets when it would rather pay the request.
    context 'with a ttl of zero' do
      subject(:cache) { described_class.new(ttl: 0) }

      it 'is disabled' do
        expect(cache).not_to be_enabled
      end

      it 'reads through every time' do
        cache.fetch('key') { 'first' }

        expect(cache.fetch('key') { 'second' }).to eq('second')
      end
    end
  end
end
