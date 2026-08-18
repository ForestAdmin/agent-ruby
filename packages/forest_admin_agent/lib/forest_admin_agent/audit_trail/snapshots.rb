module ForestAdminAgent
  module AuditTrail
    # What a "before" hook leaves for the matching "after" hook: the records as they stood, the patch, and the
    # ids of the pending rows to confirm.
    #
    # Both hooks bracket one operation on one thread, so a LIFO stack pairs them without relying on the filter
    # object reaching both unchanged. An operation raising in between strands its entry, hence the cap.
    class Snapshots
      include Recording

      # ponytail: 16 deep is far past any legitimate nesting; raise it if one ever gets that far.
      MAX_PENDING = 16

      def push(snapshot)
        stack = pending
        stack.shift while stack.size >= MAX_PENDING
        stack.push(snapshot)
      end

      def pop
        pending.pop
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
        if AuditTrail.critical?
          raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                'The audit trail is configured as critical and cannot record an operation touching more than ' \
                "#{cap} records at once. Narrow the selection."
        end

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
