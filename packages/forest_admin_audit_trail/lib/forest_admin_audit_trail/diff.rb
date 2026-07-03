module ForestAdminAuditTrail
  # Minimal structural diff. Nested hashes and arrays of hashes are recursed into, so only the
  # keys/indexes whose leaf value actually changed are kept — a single sub-field change does not
  # store the whole object/array. Scalars, primitive arrays, dates and other values are compared and
  # kept as a whole.
  #
  # Ruby's `==` already performs deep, key-order-independent equality on Hash and (ordered) equality
  # on Array, so it is used directly as the equality primitive.
  module Diff
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
        sub = diff(before[key], after[key])
        next unless sub

        previous[key] = sub[:previous]
        next_values[key] = sub[:next]
      end

      { previous: previous, next: next_values }
    end

    def diff_object_arrays(before, after)
      previous = {}
      next_values = {}

      [before.length, after.length].max.times do |index|
        sub = diff(before[index], after[index])
        next unless sub

        previous[index] = sub[:previous]
        next_values[index] = sub[:next]
      end

      { previous: previous, next: next_values }
    end

    private_class_method :diff_hashes, :diff_object_arrays
  end
end
