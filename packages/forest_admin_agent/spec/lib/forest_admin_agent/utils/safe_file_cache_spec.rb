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

      it 'propagates a read error other than a missing or corrupted file' do
        cache.set('forest.users', 'value')
        allow(File).to receive(:open).and_raise(Errno::EACCES)

        expect { cache.get('forest.users') }.to raise_error(Errno::EACCES)
      end

      it 'answers nil for a file truncated by a writer that does not rename' do
        cache.set('forest.users', { '1' => { roleId: 1 } })
        path = cache_files.first
        File.binwrite(path, File.binread(path)[0, 5])

        expect(cache.get('forest.users')).to be_nil
      end

      it 'answers nil for an empty file' do
        cache.set('forest.users', 'value')
        File.write(cache_files.first, '')

        expect(cache.get('forest.users')).to be_nil
      end

      it 'clears even when another process already removed the cache' do
        cache.set('forest.users', 'value')
        FileUtils.rm_rf(File.join(root_dir, 'permissions'))

        expect { cache.clear }.not_to raise_error
        expect(cache.get('forest.users')).to be_nil
        expect(Dir.exist?(File.join(root_dir, 'permissions'))).to be true
      end

      it 'drops the write when a concurrent clear removes the directory before the rename' do
        allow(File).to receive(:rename).and_wrap_original do |original, *paths|
          FileUtils.rm_rf(File.join(root_dir, 'permissions'))
          original.call(*paths)
        end

        expect { cache.get_or_set('forest.users') { 'value' } }.not_to raise_error
        expect(cache.get('forest.users')).to be_nil
      end

      it 'deletes a key that is not cached without raising' do
        expect { cache.delete('forest.users') }.not_to raise_error
      end

      context 'with an expiry' do
        let(:expiry) { 60 }

        it 'ignores an expired value and leaves it for the next write to replace' do
          cache.set('forest.users', 'value')
          path = cache_files.first
          File.utime(Time.now - 61, Time.now - 61, path)

          expect(cache.get('forest.users')).to be_nil
          expect(File.exist?(path)).to be true

          cache.set('forest.users', 'fresh')
          expect(cache.get('forest.users')).to eq('fresh')
        end

        it 'keeps a fresh value' do
          cache.set('forest.users', 'value')

          expect(cache.get('forest.users')).to eq('value')
        end
      end
    end
  end
end
