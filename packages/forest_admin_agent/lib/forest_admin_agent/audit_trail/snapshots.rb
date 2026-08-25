module ForestAdminAgent
  module AuditTrail
    # What a "before" hook leaves for the matching "after" hook: the records as they stood, the patch, and the
    # ids of the pending rows to confirm.
    #
    # Entries are keyed by the object the hook decorator hands to both contexts — the filter, or the data on a
    # create — because taking the newest entry is wrong as soon as writes nest: an inner write that fails skips
    # its after hook and stays on the stack, and the outer hook would then confirm the failed operation's rows
    # as done and leave its own stranded. Both directions of that are lies.
    #
    # An operation raising between the two hooks strands its entry, hence the cap; its rows stay `pending` in
    # the table, which is the truthful state for a write that may not have landed.
    class Snapshots
      include Recording

      # ponytail: 16 deep is far past any legitimate nesting; raise it if one ever gets that far.
      MAX_PENDING = 16

      def push(key, snapshot)
        stack = pending
        stack.shift while stack.size >= MAX_PENDING
        stack.push(snapshot.merge(key: key))
      end

      # The entry this operation left, or nothing rather than someone else's.
      #
      # A customization that replaced the filter or the data leaves no identity to match on: our before hook saw
      # the replacement and the after context carries the original. With a single operation in flight that is
      # unambiguous, so it still pairs; with several it does not guess, and the rows stay pending.
      def pop_for(key)
        stack = pending
        index = stack.rindex { |entry| entry[:key].equal?(key) }
        index = 0 if index.nil? && stack.size == 1

        index.nil? ? nil : stack.delete_at(index)
      end

      # The records an operation is about to touch, capped. Reading "delete all" unbounded would materialise
      # every matched row — and the pending/confirm protocol writes each of them twice. Truncation is logged
      # rather than silent: an incomplete audit somebody knows about beats an OOM.
      #
      # Read outside the write's transaction — hooks bracket the write as separate calls and the data layer
      # exposes no lock, on purpose, since it spans ActiveRecord, Mongoid, HTTP APIs. So two updates racing on
      # one record both snapshot the same state, and the one that lands second records a `previous_values` that
      # was already overwritten.
      #
      # An empty list on failure rather than no snapshot at all: the after hook pops unconditionally, so
      # skipping the push would pair it with an unrelated entry. Reading it goes through the gate, not
      # `audit_safely`: knowing what an operation is about to touch is part of being able to record it, so
      # under `critical: true` a snapshot that cannot be read refuses the operation.
      def take(context, projection)
        cap = AuditTrail::MAX_RECORDS_PER_OPERATION
        page = ForestAdminDatasourceToolkit::Components::Query::Page.new(offset: 0, limit: cap + 1)
        records = AuditTrail.gate { context.collection.list(context.filter.override(page: page), projection) } || []
        return records if records.size <= cap

        refuse_or_truncate(context, records, cap)
      end

      private

      # Truncating means the operation writes more records than it audits. Tolerable when the audit trail is
      # advisory; under `critical: true` it breaks the one invariant the mode exists for, so the operation is
      # refused instead — before the write, so there is nothing to repair.
      def refuse_or_truncate(context, records, cap)
        AuditTrail.refuse_over_cap! if AuditTrail.critical?

        kept = records.first(cap)
        AuditTrail.log_truncation(kept.size, audit_safely { count_matching(context) })

        kept
      end

      def count_matching(context)
        aggregation = ForestAdminDatasourceToolkit::Components::Query::Aggregation.new(operation: 'Count')

        context.collection.aggregate(context.filter, aggregation).first&.fetch('value', nil)
      end

      def pending
        Thread.current[:forest_audit_trail_snapshots] ||= []
      end
    end
  end
end
