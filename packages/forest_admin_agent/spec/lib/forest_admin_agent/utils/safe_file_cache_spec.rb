require 'spec_helper'
require 'tmpdir'

module ForestAdminAgent
  module Utils
    describe SafeFileCache do
      subject(:cache) { described_class.new('permissions', root_dir, expiry) }

      let(:root_dir) { Dir.mktmpdir }
      let(:expiry) { 0 }

      after { FileUtils.rm_rf(root_dir) }

      def cache_files
        Dir.glob(File.join(root_dir, '**', '*'), File::FNM_DOTMATCH).select { |path| File.file?(path) }
      end

      it 'returns what was set' do
        cache.set('forest.users', { '1' => { roleId: 1 } })

        expect(cache.get('forest.users')).to eq({ '1' => { roleId: 1 } })
      end

      it 'returns nil for a missing key without creating any directory' do
        expect(cache.get('forest.users')).to be_nil
        expect(Dir.children(File.join(root_dir, 'permissions'))).to be_empty
      end

      it 'shares its files with FileCache, so both versions of the agent read one cache' do
        FileCache.new('permissions', root_dir).set('forest.users', 'from FileCache')
        expect(cache.get('forest.users')).to eq('from FileCache')

        cache.set('forest.collections', 'from SafeFileCache')
        expect(FileCache.new('permissions', root_dir).get('forest.collections')).to eq('from SafeFileCache')
      end

      it 'keeps the previous value readable while a new one is being written' do
        cache.set('forest.users', 'old')
        seen_during_write = nil
        allow(Marshal).to receive(:dump).and_wrap_original do |original, value, io|
          seen_during_write = cache.get('forest.users')
          original.call(value, io)
        end

        cache.set('forest.users', 'new')

        expect(seen_during_write).to eq('old')
        expect(cache.get('forest.users')).to eq('new')
      end

      it 'keeps the previous value and leaves no temporary file when a write fails' do
        cache.set('forest.users', 'old')
        allow(Marshal).to receive(:dump).and_raise(IOError)

        expect { cache.set('forest.users', 'new') }.to raise_error(IOError)
        expect(cache.get('forest.users')).to eq('old')
        expect(cache_files.size).to eq(1)
      end

      it 'does not open a file to read its modification time' do
        cache.set('forest.users', 'value')
        allow(File).to receive(:new).and_call_original

        cache.get('forest.users')

        expect(File).not_to have_received(:new)
      end

      it 'answers nil when the file disappears while being read' do
        cache.set('forest.users', 'value')
        allow(File).to receive(:open).and_raise(Errno::ENOENT)

        expect(cache.get('forest.users')).to be_nil
      end

      it 'deletes a key that is not cached without raising' do
        expect { cache.delete('forest.users') }.not_to raise_error
      end

      context 'with an expiry' do
        let(:expiry) { 60 }

        it 'drops an expired value' do
          cache.set('forest.users', 'value')
          path = cache_files.first
          File.utime(Time.now - 61, Time.now - 61, path)

          expect(cache.get('forest.users')).to be_nil
          expect(File.exist?(path)).to be false
        end

        it 'keeps a fresh value' do
          cache.set('forest.users', 'value')

          expect(cache.get('forest.users')).to eq('value')
        end
      end
    end
  end
end
