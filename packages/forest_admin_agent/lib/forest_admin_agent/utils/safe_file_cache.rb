require 'filecache'
require 'securerandom'

module ForestAdminAgent
  module Utils
    # Same on-disk layout as FileCache, so processes running either version share one cache.
    class SafeFileCache < FileCache
      def get(key)
        path = path_for(key)

        if expired?(path)
          FileUtils.rm_f(path)
          return nil
        end

        File.open(path, 'rb') { |file| Marshal.load(file) } # rubocop:disable Security/MarshalLoad
      rescue Errno::ENOENT
        nil
      end

      def set(key, value)
        path = path_for(key)
        FileUtils.mkdir_p(File.dirname(path))
        temp_path = File.join(File.dirname(path), ".#{File.basename(path)}.#{Process.pid}.#{SecureRandom.hex(4)}")

        File.open(temp_path, 'wb') { |file| Marshal.dump(value, file) }
        File.rename(temp_path, path)
      ensure
        FileUtils.rm_f(temp_path) if temp_path
      end

      def delete(key)
        FileUtils.rm_f(path_for(key))
      end

      private

      def path_for(key)
        md5 = Digest::MD5.hexdigest(key.to_s)

        File.join(get_root, *md5[0...@depth].chars, md5)
      end

      def expired?(path)
        @expiry.positive? && Time.now - File.mtime(path) >= @expiry
      end
    end
  end
end
