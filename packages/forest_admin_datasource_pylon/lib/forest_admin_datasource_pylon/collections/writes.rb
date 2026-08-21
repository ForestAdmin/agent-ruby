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

      # How many records one filter-driven update or delete may reach. Pylon
      # writes one record per request against a budget of 10 to 20 requests per
      # minute, so a wider selection is refused rather than written halfway.
      MAX_WRITE_TARGETS = 20

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

        ids = ids_for(caller, filter)
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

      def max_write_targets = MAX_WRITE_TARGETS

      # How many named ids the collection's own read can resolve exactly. `nil`
      # is no bound: the search endpoint filters `id` server-side, so any id list
      # costs one request per chunk. A collection reading an id through its own
      # endpoint overrides this with its fan-out cap — past it the read truncates,
      # and a truncated resolution writes to part of a selection it reports whole.
      def max_resolvable_ids = nil

      # The records a filter-driven write applies to: exact, or refused — the
      # caller writes one request per id and reports success for the whole
      # selection, so a subset may never be answered quietly.
      #
      # An `id equals`/`id in` filter alone — what the record detail and the bulk
      # selection send — costs no request. Anything else goes through `list`.
      def ids_for(caller, filter)
        tree = filter&.condition_tree
        if (named = id_values(tree)) && no_search?(filter)
          refuse_too_many_targets(named.size) if named.size > max_write_targets
          return named
        end

        named_count = max_resolvable_ids && filtered_ids(tree)&.size
        refuse_unresolvable_selection(named_count) if named_count && named_count > max_resolvable_ids
        resolve_ids_by_list(caller, filter)
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
      def resolve_ids_by_list(caller, filter)
        window  = Page.new(offset: 0, limit: max_write_targets + 1)
        query   = (filter || Filter.new).override(page: window)
        records = list(caller, query, Projection.new(['id']))
        refuse_unbounded_targets if records.size > max_write_targets

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
      # record where an id is read through its own endpoint — which
      # `max_write_targets` does not count, so a wide update naming such a field
      # spends two requests per record against the write budget.
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
      def refuse_too_many_targets(count)
        refuse_write_reach("applies to #{count} #{name} records, more than the #{max_write_targets} one pass covers")
      end

      # The resolution only knows the selection overflows: reporting the size of
      # its window would name 21 records to a selection holding thousands.
      def refuse_unbounded_targets
        refuse_write_reach("applies to more than the #{max_write_targets} #{name} records one pass covers")
      end

      def refuse_write_reach(reach)
        raise UnsupportedWriteError,
              "This write #{reach}: Pylon writes one record per request, against a budget of ten to twenty " \
              'requests per minute, and a write stopping halfway would report a success it did not perform. ' \
              'Narrow the selection to reach the records past this point.'
      end

      # How many of the named ids the rest of the filter matches is unknown here,
      # so the count is reported as what it is: records named.
      def refuse_unresolvable_selection(count)
        raise UnsupportedWriteError,
              "This write names #{count} #{name} records and filters them further, which #{name} answers with " \
              "one request per named record, more than the #{max_resolvable_ids} one pass reads: the resolution " \
              'would stop short and the write would then cover part of the selection while reporting all of ' \
              'it. Select fewer records, or drop the other conditions to write the ones named.'
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
