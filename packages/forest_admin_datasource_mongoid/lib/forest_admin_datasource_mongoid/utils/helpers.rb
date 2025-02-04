module ForestAdminDatasourceMongoid
  module Utils
    module Helpers
      # Similar to projection.unnest
      # @example
      # unnest(['firstname', 'book.title', 'book.author'], 'book') == ['title', 'author']
      def unnest(strings, prefix)
        strings.select { |field| field.start_with?("#{prefix}.") }.map { |field| field[prefix.size + 1..] }
      end

      def escape(str)
        str.tr('.', '_')
      end

      def recursive_delete(target, path)
        index = path.index('.')

        if index.nil?
          target.delete(path)
        else
          prefix = path[0, index]
          suffix = path[index + 1..]

          if target.is_a?(Hash) && target.key?(prefix)
            recursive_delete(target[prefix], suffix)
            target.delete(prefix) if target[prefix].empty?
          end
        end
      end
    end
  end
end
