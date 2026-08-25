module ForestAdminDatasourcePylon
  module Collections
    # The write half of every Pylon collection. Included by `BaseCollection`, so
    # a collection only declares the client calls, through the `*_record` hooks,
    # and the fields Pylon accepts in one direction only. A hook left alone
    # refuses the verb — no POST or DELETE on users, no DELETE on teams —
    # instead of the contract's NotImplementedError, read by the agent as a 500.
    #
    # What may be written is `is_read_only` on the column, the way `api_filters`
    # is what may be filtered: no second list to keep in step with the schema.
    module Writes # rubocop:disable Metrics/ModuleLength
      # Re-declared rather than borrowed from BaseCollection: a method defined
      # here resolves a constant against this module and its ancestors, never
      # against the class including it.
      Filter     = ForestAdminDatasourceToolkit::Components::Query::Filter
      Page       = ForestAdminDatasourceToolkit::Components::Query::Page
      Projection = ForestAdminDatasourceToolkit::Components::Query::Projection
      Leaf       = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
      Operators  = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators

      # What one filter-driven update or delete may spend, in requests. Pylon
      # writes one record per request, so a selection costing more than this is
      # refused rather than written halfway.
      #
      # The cap is about the round-trips, not the quota: `RateLimiter` spaces the
      # requests out inside the documented budget, which no pass this size comes
      # near — but no throttling makes a hundred sequential writes a wait the
      # operator watches, or a request the agent times out on first. Refusing is
      # the honest answer where a partial write is not recoverable.
      #
      # The budget covers the whole pass, not its writes: where a record is read
      # through its own endpoint, resolving the selection costs a request per
      # record and reading a stored value costs another, so a cap counting the
      # writes alone would let one pass spend three times this.
      MAX_WRITE_REQUESTS = 20

      # The refusal comes before the payload and the ids: everything on the way
      # there answers with something else — a count, a field of the wrong
      # direction — for a selection that was never the problem.
      def create(_caller, data)
        refuse_write('created') unless write_endpoint?(:create_record)

        serialize(create_record(build_payload(writable_attributes(data), :create)))
      rescue APIError => e
        surface_write_rejection(e)
      end

      # What the patch may write is settled before the ids are, so a patch naming
      # nothing writable is not refused for reaching too many records.
      def update(caller, filter, patch)
        refuse_write('updated') unless write_endpoint?(:update_record)

        attributes = writable_attributes(patch)
        return if attributes.empty?

        ids = ids_for(caller, filter, extra_reads: stored_read?(attributes) ? 1 : 0)
        return if ids.empty?

        payload = build_payload(attributes, :update, caller: caller, ids: ids)
        return if payload.empty?

        write_each(ids, 'updated') { |id| update_record(id, payload) }
      end

      def delete(caller, filter)
        refuse_write('deleted') unless write_endpoint?(:delete_record)

        write_each(ids_for(caller, filter), 'deleted') { |id| delete_record(id) }
      end

      protected

      # One Pylon write endpoint each, overridden by the collections having one.
      def create_record(_payload) = refuse_write('created')
      def update_record(_id, _payload) = refuse_write('updated')
      def delete_record(_id) = refuse_write('deleted')

      # The Forest schema carries a single read-only flag per column, so both
      # directions offer these; the two lists tell them apart at write time.
      def create_only_fields = [].freeze
      def update_only_fields = [].freeze

      # Columns whose Pylon write name differs from the one they are read under.
      def payload_renames = {}.freeze

      # What reading one record costs here. Nothing where the search endpoint
      # filters `id`, a whole selection travelling in one request whatever its
      # size; one request where an id is read through its own endpoint.
      def requests_per_record_read = 0

      # How many records one write may reach: the budget divided by what each of
      # them costs — the write itself, plus the `reads` the path still owes it.
      def max_write_targets(reads: 0)
        MAX_WRITE_REQUESTS / (1 + (reads * requests_per_record_read))
      end

      # How many ids a filter may name before the resolution is refused rather
      # than spent: the same reach, a named id being read before it is written
      # to. `nil` is no bound, a read costing nothing per record.
      def max_resolvable_ids(reads: 0)
        return nil if requests_per_record_read.zero?

        max_write_targets(reads: reads)
      end

      # The records a filter-driven write applies to: exact, or refused — the
      # caller writes one request per id and reports success for the whole
      # selection, so a subset may never be answered quietly.
      #
      # An `id equals`/`id in` filter alone — what the record detail and the bulk
      # selection send — costs no request. Anything else goes through `list`.
      def ids_for(caller, filter, extra_reads: 0)
        tree = filter&.condition_tree
        if (named = id_values(tree)) && no_search?(filter)
          cap = max_write_targets(reads: extra_reads)
          refuse_too_many_targets(named.size, cap) if named.size > cap
          return named
        end

        # A selection naming ids is resolved by reading each of them; any other
        # one by a single page of the collection's own read, whose cost does not
        # grow with the count.
        named_ids = filtered_ids(tree)
        reads     = extra_reads + (named_ids ? 1 : 0)
        bound     = named_ids && max_resolvable_ids(reads: reads)
        refuse_unresolvable_selection(named_ids.size, bound) if bound && named_ids.size > bound

        resolve_ids_by_list(caller, filter, reads: reads)
      end

      private

      # The `*_record` hook is the declaration that the collection wired the
      # endpoint, read here rather than repeated in a list of supported verbs.
      def write_endpoint?(hook)
        method(hook).owner != Writes
      end

      # One request per record, so a failure on the k-th leaves the k-1 before it
      # written. The error names them: raising the API error alone reads as
      # "nothing happened", and retrying on that reading would write them twice.
      def write_each(ids, verb)
        written = []

        ids.each do |id|
          yield id
          written << id
        rescue APIError => e
          # Always raises, so nothing reaches the partial report below: with no
          # record written the failure is the whole of what happened.
          surface_write_rejection(e) if written.empty?

          refuse_partial_write(verb, written, id, ids.size, e)
        end
      end

      # A 4xx names something the operator did, and travels as the
      # ValidationError whose message the agent surfaces where the APIError it
      # arrived as would be answered with 'Unexpected error'. Anything else is
      # Pylon or the network failing, which no edit of theirs would change.
      #
      # Only the write goes through here: a 4xx raised while resolving the
      # selection still reaches them as a 500, reporting a read failure as a
      # refused write being the worse of the two.
      def surface_write_rejection(error)
        raise error unless (400..499).cover?(error.status.to_i)

        raise WriteRejectedError, error.message
      end

      # One record past the cap is asked for, so an overflow is seen rather than
      # guessed from a full page.
      def resolve_ids_by_list(caller, filter, reads:)
        cap     = max_write_targets(reads: reads)
        window  = Page.new(offset: 0, limit: cap + 1)
        query   = (filter || Filter.new).override(page: window)
        records = list(caller, query, Projection.new(['id']))
        refuse_unbounded_targets(cap) if records.size > cap

        records.filter_map { |record| record['id'] }.uniq
      end

      # The ids a filter names, as a leaf of its own or inside a top-level `and`.
      # Unlike `extract_id_lookup`, nothing is asserted about the rest of the
      # tree — the leftovers travel to `list` — nor about the sibling conditions,
      # so this counts records *named*, never records the write applies to. The
      # first id leaf of an `and` of two wins, over-refusing a narrower one.
      def filtered_ids(node)
        named = id_values(node)
        return named if named
        return nil unless and_branch?(node)

        Array(node.conditions).filter_map { |child| id_values(child) }.first
      end

      # The writable attributes, in the shape the endpoint takes them.
      def build_payload(attributes, direction, caller: nil, ids: [])
        attrs = honour_write_direction(attributes, direction, caller, ids)
        # Pylon fills in what a create leaves out; on an update a nil is the
        # operator clearing a value, so it travels.
        attrs = attrs.compact if direction == :create

        custom, native = split_custom_fields(attrs)
        payload = native.transform_keys { |field| payload_renames.fetch(field, field) }
        payload['custom_fields'] = custom unless custom.empty?
        payload
      end

      # Everything else is dropped rather than refused: the front sends the
      # fields of its form, and a read-only one reaching the payload is the
      # agent's doing, not a request the operator made.
      def writable_attributes(data)
        attrs = data.is_a?(Hash) ? data.transform_keys(&:to_s) : {}

        attrs.select { |field, _value| writable_column?(field) }
      end

      def writable_column?(field)
        column = schema[:fields][field]

        column&.type == 'Column' && !column.is_read_only
      end

      # Whether the patch will have `stored_values` read every record it reaches
      # before a field of the wrong direction is dropped or refused, which the
      # cap has to charge it for: see `ids_for`.
      def stored_read?(attributes) = (attributes.keys & create_only_fields).any?

      # A field of the other direction is dropped when it asks for nothing, and
      # refused when the operator really changed it: answering an edit with a
      # success Pylon did not perform is worse than an error naming the field.
      #
      # Only a create can tell without reading, Pylon filling it in with exactly
      # what a blank value asks for. On an update the stored value is what
      # settles it — an unchecked box is nothing over a stored `false`, and a
      # real edit over a stored `true`.
      def honour_write_direction(attrs, direction, caller, ids)
        wrong = attrs.keys & (direction == :create ? update_only_fields : create_only_fields)
        return attrs if wrong.empty?

        asked = if direction == :create
                  wrong.reject { |field| blank_write_value?(attrs[field]) }
                else
                  wrong - unchanged_fields(caller, ids, wrong, attrs)
                end
        refuse_wrong_direction(asked, direction) unless asked.empty?

        attrs.except(*wrong)
      end

      # What a form sends for a field the operator never touched: no value at
      # all, an unchecked box, an empty list. A `0` or a string is a value only
      # the other endpoint could write.
      def blank_write_value?(value)
        return true if value.nil? || value == false
        return value.empty? if value.respond_to?(:empty?)

        false
      end

      # The wrong-direction fields already holding the value the patch asks for.
      # One record the read did not hand back is enough to refuse them all:
      # nothing here may claim a value is unchanged on a record it never read.
      def unchanged_fields(caller, ids, fields, attrs)
        return [] if fields.empty?

        stored = stored_values(caller, ids, fields)
        return [] if stored.size < ids.size

        fields.select { |field| stored.all? { |record| same_write_value?(record[field], attrs[field]) } }
      end

      # Two blanks are the same state: Pylon returns a null where the form sends
      # `false` or an empty string for the same untouched field. Strings are
      # compared stripped, `body_html` travelling through an editor that may hand
      # back the markup it was given re-indented — and refusing an edit nobody
      # made is the one error the operator cannot act on.
      def same_write_value?(stored, asked)
        return true if blank_write_value?(stored) && blank_write_value?(asked)
        return stored.to_s.strip == asked.to_s.strip if stored.is_a?(String) || asked.is_a?(String)

        stored == asked
      end

      # Read only when the patch names a field of the wrong direction, and only
      # for those fields. One request where the endpoint filters `id`, one per
      # record where an id is read through its own endpoint — which the cap does
      # charge the patch for, `stored_read?` declaring it before the ids are
      # resolved.
      #
      # By id rather than through the caller's filter: that filter was already
      # resolved into these ids, so re-running it would spend those requests
      # twice and, carrying no page, walk every record it matches.
      def stored_values(caller, ids, fields)
        query = Filter.new(condition_tree: Leaf.new('id', Operators::IN, ids),
                           page: Page.new(offset: 0, limit: ids.size))

        list(caller, query, Projection.new(['id'] + fields))
      end

      # Pylon reads its custom fields back as a map indexed by slug and writes
      # them as a list, `values` for a multi-value field and `value` for every
      # other — a select by the slug of its option, what the Enum advertises.
      def split_custom_fields(attrs)
        by_column = custom_fields_by_column
        entries = []

        native = attrs.each_with_object({}) do |(field, value), rest|
          custom_field = by_column[field]
          custom_field ? entries << custom_field_entry(custom_field, value) : rest[field] = value
        end

        [entries, native]
      end

      def custom_fields_by_column
        @custom_fields_by_column ||= custom_fields.to_h { |field| [field[:column_name], field] }
      end

      def custom_field_entry(custom_field, value)
        slug = custom_field[:column_name]
        return { 'slug' => slug, 'values' => Array(value) } if custom_field[:multi_value]

        { 'slug' => slug, 'value' => value }
      end

      def refuse_write(verb)
        raise UnsupportedWriteError,
              "A #{name} record cannot be #{verb}: the Pylon API exposes no endpoint for it."
      end

      # Every offending field at once: refusing them one at a time would have the
      # operator undo one, retry, and learn about the next.
      def refuse_wrong_direction(fields, direction)
        them = fields.one? ? 'it' : 'them'
        detail = if direction == :create
                   "Pylon only accepts #{them} on an existing record: create the record, then edit it."
                 else
                   "Pylon only accepts #{them} when the record is created, and exposes no endpoint to change " \
                     "#{them} afterwards."
                 end

        named = fields.map { |field| "'#{field}'" }.join(', ')
        raise UnsupportedWriteError, "#{named} cannot be set here on a #{name}: #{detail}"
      end

      # The count is exact here, the filter having named the ids.
      def refuse_too_many_targets(count, cap)
        refuse_write_reach("applies to #{count} #{name} records, more than the #{cap} one pass covers")
      end

      # The resolution only knows the selection overflows: reporting the size of
      # its window would name 21 records to a selection holding thousands.
      def refuse_unbounded_targets(cap)
        refuse_write_reach("applies to more than the #{cap} #{name} records one pass covers")
      end

      def refuse_write_reach(reach)
        raise UnsupportedWriteError,
              "This write #{reach}: Pylon writes one record per request, and a write stopping halfway — on a " \
              'timeout, or on the first record Pylon refuses — would report a success it did not perform. ' \
              'Narrow the selection to reach the records past this point.'
      end

      # How many of the named ids the rest of the filter matches is unknown here,
      # so the count is reported as what it is: records named.
      def refuse_unresolvable_selection(count, bound)
        raise UnsupportedWriteError,
              "This write names #{count} #{name} records and filters them further, which #{name} answers with " \
              "one request per named record, on top of the one each write costs: more than the #{bound} one " \
              'pass covers. Select fewer records, or drop the other conditions to write the ones named.'
      end

      def refuse_partial_write(verb, written, failed_id, total, error)
        raise PartialWriteError,
              "#{written.size} of #{total} #{name} records were #{verb} and then '#{failed_id}' failed: " \
              "#{error.message}. The records already #{verb} are #{written.join(", ")}, and they stay " \
              "#{verb} — the ones after them were left untouched. Retry the write on the untouched records " \
              "alone: retrying the whole selection would perform it twice on the ones already #{verb}."
      end
    end
  end
end
