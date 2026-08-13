module ForestAdminAgent
  module AuditTrail
    # Minimal structural diff. Nested hashes and arrays of hashes are recursed into, so only the
    # keys/indexes whose leaf value actually changed are kept — a single sub-field change does not
    # store the whole object/array. Scalars, primitive arrays, dates and other values are compared and
    # kept as a whole.
    #
    # Ruby's `==` already performs deep, key-order-independent equality on Hash and (ordered) equality
    # on Array, so it is used directly as the equality primitive.
    module Diff
      # A key that does not exist on one side of the diff. It is never stored: the key is simply left out
      # of that side's hash, so `{"flag" => nil}` (a key holding nil) and `{}` (no key) stay tellable
      # apart in the database — which a revert needs and a string sentinel would only fake.
      ABSENT = Object.new.freeze

      module_function

      # @return [Hash{Symbol=>Object}, nil] { previous:, next: } of the changed leaves, or nil when equal.
      def diff(before, after)
        return nil if before == after

        return diff_hashes(before, after) if before.is_a?(Hash) && after.is_a?(Hash)

        return diff_object_arrays(before, after) if object_array?(before) && object_array?(after)

        { previous: before.nil? ? nil : before, next: after.nil? ? nil : after }
      end

      # Build the previous/new value hashes for the writable columns that actually changed.
      #
      # @param before [Hash] snapshot of the record before the change (string keys)
      # @param patch [Hash] the values being written (string keys); only present keys are considered
      # @param columns [Array<String>] writable column names to inspect
      # @return [Hash{Symbol=>Hash}] { previous_values:, new_values: }
      def changed_values(before, patch, columns)
        previous_values = {}
        new_values = {}

        columns.each do |column|
          delta = patch.key?(column) ? diff(before[column], patch[column]) : nil
          next unless delta

          previous_values[column] = delta[:previous]
          new_values[column] = delta[:next]
        end

        { previous_values: previous_values, new_values: new_values }
      end

      # Arrays whose every element is a hash (record-like collections, e.g. a workflow history).
      def object_array?(value)
        value.is_a?(Array) && !value.empty? && value.all?(Hash)
      end

      def diff_hashes(before, after)
        previous = {}
        next_values = {}

        (before.keys | after.keys).each do |key|
          sub = diff_at(before, after, key)
          next unless sub

          previous[key] = sub[:previous] unless sub[:previous].equal?(ABSENT)
          next_values[key] = sub[:next] unless sub[:next].equal?(ABSENT)
        end

        { previous: previous, next: next_values }
      end

      # A key held with a nil value is not the same thing as a missing key: recursing on the values alone
      # reads both as nil and reports no change at all.
      def diff_at(before, after, key)
        return diff(before[key], after[key]) if before.key?(key) == after.key?(key)

        {
          previous: before.key?(key) ? before[key] : ABSENT,
          next: after.key?(key) ? after[key] : ABSENT
        }
      end

      def diff_object_arrays(before, after)
        previous = {}
        next_values = {}

        [before.length, after.length].max.times do |index|
          sub = diff(before[index], after[index])
          next unless sub

          # Same rule as for hash keys: an index one side does not reach is left out of that side, so a
          # revert can tell an appended element (drop it) from one whose value became nil (keep it).
          previous[index] = sub[:previous] if index < before.length
          next_values[index] = sub[:next] if index < after.length
        end

        { previous: previous, next: next_values }
      end

      # Undo one recorded change: given the value as it stands now and the two sides of the diff that
      # produced it, return the value as it was before. Nested hashes are walked so untouched keys keep
      # their current value; a key missing from `previous` was added by the change, so it goes away.
      #
      # @param current [Object] the value as it stands now (may be nil when the record is gone)
      # @param previous [Object] the `previous_values` side of the recorded diff
      # @param changed [Object] the `new_values` side of the recorded diff
      def revert(current, previous, changed)
        return revert_array(current, previous, changed) if current.is_a?(Array) && partial?(previous, changed)
        return revert_hash(current, previous, changed) if current.is_a?(Hash) && partial?(previous, changed)

        previous
      end

      # Both sides being hashes is what `diff` emits for a structural diff; anything else replaced the
      # value as a whole.
      def partial?(previous, changed)
        previous.is_a?(Hash) && changed.is_a?(Hash)
      end

      def revert_hash(current, previous, changed)
        (previous.keys | changed.keys).each_with_object(current.dup) do |key, result|
          if previous.key?(key)
            result[key] = revert(current[key], previous[key], changed[key])
          else
            # Only the change introduced this key, so before the change there was none.
            result.delete(key)
          end
        end
      end

      # Arrays of objects are diffed index by index, and JSON turns those indexes into strings on the way
      # back out. Highest index first, so dropping an element the change appended leaves the lower ones
      # where the diff expects them.
      def revert_array(current, previous, changed)
        indexes = (previous.keys | changed.keys).map(&:to_i).sort.reverse

        indexes.each_with_object(current.dup) do |index, result|
          if index?(previous, index)
            result[index] = revert(current[index], at(previous, index), at(changed, index))
          else
            result.delete_at(index)
          end
        end
      end

      def index?(hash, index)
        hash.key?(index) || hash.key?(index.to_s)
      end

      def at(hash, index)
        hash.key?(index) ? hash[index] : hash[index.to_s]
      end

      private_class_method :diff_hashes, :diff_at, :diff_object_arrays, :partial?, :revert_hash,
                           :revert_array, :index?, :at
    end
  end
end
