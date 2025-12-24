module ForestAdminDatasourceMongoid
  module Utils
    module Helpers
      # Similar to projection.unnest
      # @example
      # unnest(['firstname', 'book.title', 'book.author'], 'book') == ['title', 'author']
      def unnest(strings, prefix)
        prefix_with_dot = "#{prefix}."
        strings.filter_map { |field| field[(prefix.size + 1)..] if field.start_with?(prefix_with_dot) }
      end

      def escape(str)
        str.tr('.', '_')
      end

      def recursive_set(target, path, value)
        index = path.index('.')
        if index.nil?
          target[path] = value
        else
          prefix = path[0, index]
          suffix = path[index + 1, path.length]
          target[prefix] ||= {}
          recursive_set(target[prefix], suffix, value)
        end
      end

      def recursive_delete(target, path)
        index = path.index('.')

        if index.nil?
          target.delete(path)
        else
          prefix = path[0..(index - 1)]
          suffix = path[(index + 1)..]

          if target.is_a?(Hash) && target.key?(prefix)
            recursive_delete(target[prefix], suffix)
            target.delete(prefix) if target[prefix].empty?
          end
        end
      end

      # not sure it this method is relevant for mongoid
      def replace_mongo_types(data)
        case data
        when BSON::ObjectId, BSON::Decimal128
          data.to_s
        when Date, Time
          data.iso8601
        when Array
          data.map { |item| replace_mongo_types(item) }
        when Hash
          data.transform_values { |value| replace_mongo_types(value) }
        else
          data
        end
      end

      # Unflattend patches and records
      def unflatten_record(record, as_fields, patch_mode: false)
        new_record = record.dup

        as_fields.each do |field|
          alias_field = field.gsub('.', '@@@')

          value = new_record[alias_field]

          next if value.nil?

          if patch_mode
            new_record[field] = value
          else
            recursive_set(new_record, field, value)
          end

          new_record.delete(alias_field)
        end

        new_record
      end

      def reformat_patch(patch)
        patch.each_with_object({}) do |(key, value), result|
          keys = key.split('.')
          last_key = keys.pop
          nested_hash = keys.reverse.inject({ last_key => value }) do |hash, k|
            { k => hash }
          end
          deep_merge(result, nested_hash)
        end
      end

      def deep_merge(target, source)
        source.each do |key, value|
          if target[key].is_a?(Hash) && value.is_a?(Hash)
            deep_merge(target[key], value)
          else
            target[key] ||= value
          end
        end
        target
      end

      # Compare two ids.
      # This is useful to ensure we perform array operations in the right order.
      #
      # @example
      # compareIds('a.20.a', 'a.1.b') => 1 (because 1 < 20)
      # compareIds('a.0.a', 'b.1.b') => -1 (because 'a' < 'b')
      def compare_ids(id_a, id_b)
        parts_a = id_a.split('.')
        parts_b = id_b.split('.')
        length = [parts_a.length, parts_b.length].min

        (0...length).each do |i|
          # if both parts are numbers, we compare them numerically
          result = if parts_a[i] =~ /^\d+$/ && parts_b[i] =~ /^\d+$/
                     parts_a[i].to_i <=> parts_b[i].to_i
                   else
                     # else, we compare as strings
                     parts_a[i] <=> parts_b[i]
                   end
          return result unless result.zero?
        end

        parts_a.length <=> parts_b.length
      end

      def split_id(id)
        dot_index = id.index('.')
        root_id = id[0...dot_index]
        path = id[(dot_index + 1)..]

        root_id = BSON::ObjectId.from_string(root_id) if BSON::ObjectId.legal?(root_id)

        [root_id, path]
      end

      def group_ids_by_path(ids)
        updates = Hash.new { |hash, key| hash[key] = [] }

        ids.each do |id|
          root_id, path = split_id(id)
          updates[path] << root_id
        end

        updates
      end
    end
  end
end
