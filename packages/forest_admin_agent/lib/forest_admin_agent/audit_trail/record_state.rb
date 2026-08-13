module ForestAdminAgent
  module AuditTrail
    # Rebuilds a record as it stood at a given instant by walking its history backwards from the record as
    # it stands now, undoing every entry recorded after that instant (newest first).
    #
    # Only audited columns are reconstructed — read-only, computed and DB-managed fields are never recorded,
    # so they cannot be restored.
    module RecordState
      module_function

      # @param current [Hash, nil] the record as it stands now, nil when it no longer exists
      # @param entries [Array<AuditRecord>] entries recorded after the instant, newest first
      # @return [Hash, nil] the record at that instant, nil when it did not exist then
      def at(current, entries)
        entries.reduce(current) { |state, entry| undo(state, entry) }
      end

      def undo(state, entry)
        case entry.operation
        when 'create'
          # Created after the instant, so it did not exist then. An older entry can still bring a previous
          # life of the same id back — the walk carries on.
          nil
        when 'delete'
          # The delete recorded the whole record, which is exactly the state it was deleted from.
          entry.previous_values
        when 'update'
          revert_columns(state, entry)
        else
          # Action rows carry no field change.
          state
        end
      end

      def revert_columns(state, entry)
        entry.previous_values.each_with_object((state || {}).dup) do |(column, previous), result|
          result[column] = Diff.revert(result[column], previous, entry.new_values[column])
        end
      end
    end
  end
end
