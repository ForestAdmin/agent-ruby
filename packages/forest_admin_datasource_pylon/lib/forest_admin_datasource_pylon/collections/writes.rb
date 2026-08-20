module ForestAdminDatasourcePylon
  module Collections
    # The write half of every Pylon collection: `create`, `update` and `delete`,
    # the payload they send, and the ids a filter-driven write applies to.
    #
    # Included by `BaseCollection`, so the mechanism is shared and each
    # collection only declares what belongs to it: the client calls, through the
    # `*_record` hooks, and the handful of fields Pylon accepts in one direction
    # only. A hook a collection leaves alone refuses the verb, which is how the
    # collections Pylon exposes no endpoint for — no POST or DELETE on users, no
    # DELETE on teams — answer with a message instead of the contract's
    # NotImplementedError, read by the agent as an unexpected 500.
    #
    # What may be written is not a list kept here: it is `is_read_only` on the
    # column, the same way `api_filters` is the single source of truth for what
    # may be filtered. A column the schema declares read-only is dropped from
    # the payload, whether it is native, a foreign key or a custom field.
    #
    # Long by line count only: three verbs, the payload they share, and the
    # refusals naming what Pylon cannot do.
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
      # minute, so a wider selection is refused rather than written halfway:
      # a delete that stopped in the middle of the page would look done and
      # would not be, which is the very thing this datasource refuses.
      MAX_WRITE_TARGETS = 20

      # A verb Pylon has no endpoint for is refused first, before the payload is
      # built and before the ids are resolved: the refusal holds whatever the
      # selection turns out to be, and everything the write would do on the way
      # there answers with something else — the cap naming a count, a field of
      # the wrong direction naming a field — sending the operator to narrow a
      # selection that was never the problem.
      def create(_caller, data)
        refuse_write('created') unless write_endpoint?(:create_record)

        serialize(create_record(build_payload(writable_attributes(data), :create)))
      rescue APIError => e
        surface_write_rejection(e)
      end

      # What the patch may write is settled before the ids are: a patch naming
      # nothing writable sends no request and, more to the point, is not refused
      # for reaching too many records — the cap bounds a write, and there is
      # none here.
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

      # The fields Pylon accepts on one endpoint and not on the other. The Forest
      # schema carries a single read-only flag per column, so both directions
      # offer them; these two lists are what tells them apart at write time.
      def create_only_fields = [].freeze
      def update_only_fields = [].freeze

      # Columns whose Pylon write name differs from the one they are read under.
      def payload_renames = {}.freeze

      def max_write_targets = MAX_WRITE_TARGETS

      # How many named ids the collection's own read can resolve exactly. `nil`
      # is no bound at all, the default: the search endpoint filters `id`
      # server-side, so any id list is answered by one request per chunk. The
      # collection resolving a named id by its own endpoint overrides this with
      # its fan-out cap — past it the read truncates, and a truncated resolution
      # would write to part of the selection while reporting the whole of it.
      def max_resolvable_ids = nil

      # The records a filter-driven write applies to: exact, or refused. Nothing
      # here may quietly answer with a subset — the caller writes one request per
      # id and reports success for the whole selection.
      #
      # An `id equals`/`id in` filter alone is answered without a single request:
      # that is what the record detail and the bulk selection of the UI send, and
      # reading them back to learn ids they just named would spend the budget the
      # writes themselves need. Anything else — a scope, a segment, a search, a
      # condition on another column — is resolved by the collection's own `list`,
      # so the scope applies and the endpoint filters what it can.
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

      # Whether the collection wired the Pylon endpoint for a verb. The
      # `*_record` hook is the declaration, read here rather than repeated in a
      # list of supported verbs a collection would have to keep in step with its
      # own hooks — the same reason `is_read_only` on the column, and not a
      # second list of writable names, is what the payload builder reads.
      def write_endpoint?(hook)
        method(hook).owner != Writes
      end

      # One request per record, so a failure on the k-th record leaves the k-1
      # before it written — the cap bounds how many records a write reaches,
      # nothing bounds the endpoint answering 429 or 422 halfway through. The
      # error names the records that landed: raising the API error alone reads
      # as "the write failed, nothing happened", and retrying the selection on
      # that reading would write them a second time.
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

      # Pylon's own refusal, in the operator's hands. A 4xx names something they
      # did — a required field left out, a value the endpoint does not take, a
      # record already gone — and travels as the ValidationError whose message
      # the agent surfaces, where the APIError it arrived as would be answered
      # with 'Unexpected error'. Anything else is Pylon or the network failing,
      # which no edit of theirs would change: it stays what it was.
      def surface_write_rejection(error)
        raise error unless (400..499).cover?(error.status.to_i)

        raise WriteRejectedError, error.message
      end

      # One record past the cap is asked for, so an overflow is seen rather than
      # guessed from a full page — the same bound `foreign_keys_matching` puts on
      # a resolved relation condition.
      def resolve_ids_by_list(caller, filter)
        window  = Page.new(offset: 0, limit: max_write_targets + 1)
        query   = (filter || Filter.new).override(page: window)
        records = list(caller, query, Projection.new(['id']))
        refuse_too_many_targets(records.size) if records.size > max_write_targets

        records.filter_map { |record| record['id'] }.uniq
      end

      # The ids a filter names, whether as a leaf of its own or inside a
      # top-level `and`. Unlike `extract_id_lookup`, nothing is asserted about
      # what the rest of the tree can be applied in memory: the leftovers travel
      # to `list`, which answers them the way a read does — server-side where the
      # endpoint filters `id`, through the primary-key short-circuit where it
      # does not. Nothing is asserted about the sibling conditions either, so
      # this is a count of records *named*, never of records the write applies
      # to: it answers what `max_resolvable_ids` needs, not what the cap does.
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

      # Keys the schema declares writable, custom fields included. Everything
      # else is dropped rather than refused: the front sends the fields of its
      # form, and a read-only one reaching the payload is the agent's doing, not
      # a request the operator made.
      def writable_attributes(data)
        attrs = data.is_a?(Hash) ? data.transform_keys(&:to_s) : {}

        attrs.select { |field, _value| writable_column?(field) }
      end

      def writable_column?(field)
        column = schema[:fields][field]

        column&.type == 'Column' && !column.is_read_only
      end

      # A field of the other direction is dropped when it asks for nothing, and
      # refused when the operator really changed it: Pylon cannot write it, and
      # answering the edit with a success it did not perform is worse than an
      # error naming the field.
      #
      # What "asks for nothing" means differs by direction, and only a create
      # can tell without reading. Pylon fills a create in with exactly what a
      # blank value asks for, so a blank one is dropped there. On an update the
      # record already holds a value, and the only thing that settles whether
      # the patch changes it is that value: an unchecked box is nothing to write
      # over a stored `false`, and a real edit over a stored `true`. Blankness
      # alone would drop the second, reporting an edit Pylon never performed.
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
      # An unreadable record counts as none of them: the field is refused rather
      # than dropped, since nothing here may claim a value is unchanged without
      # having read it.
      def unchanged_fields(caller, ids, fields, attrs)
        return [] if fields.empty?

        stored = stored_values(caller, ids, fields)
        return [] if stored.empty?

        fields.select { |field| stored.all? { |record| same_write_value?(record[field], attrs[field]) } }
      end

      # Whether the patch asks for the value the record already holds.
      #
      # Two blanks are the same state: Pylon returns a null where the form sends
      # `false` or an empty string for the same untouched field, and refusing
      # that pair would fail every edit whose form carries one.
      #
      # Strings are compared stripped: `body_html` travels through an editor
      # that may hand back the markup it was given re-indented, and refusing an
      # edit nobody made — naming a field the operator never touched — is the
      # one error they cannot act on.
      def same_write_value?(stored, asked)
        return true if blank_write_value?(stored) && blank_write_value?(asked)
        return stored.to_s.strip == asked.to_s.strip if stored.is_a?(String) || asked.is_a?(String)

        stored == asked
      end

      # Read only when the patch names a field of the wrong direction, and only
      # for those fields: an update naming none costs no request at all. It is
      # one request on the collections whose endpoint filters `id`, and one per
      # record on the ones reading an id through its own endpoint — PylonIssue,
      # whose fan-out `max_resolvable_ids` bounds.
      #
      # Read by id rather than through the caller's filter: the filter was
      # already resolved into these ids, so re-running it would spend those
      # requests a second time and — carrying no page of its own — walk every
      # record it matches rather than the handful about to be written.
      def stored_values(caller, ids, fields)
        query = Filter.new(condition_tree: Leaf.new('id', Operators::IN, ids),
                           page: Page.new(offset: 0, limit: ids.size))

        list(caller, query, Projection.new(['id'] + fields))
      end

      # Pylon reads its custom fields back as a map indexed by slug and writes
      # them as a list, one entry per field, carrying `values` for a multi-value
      # field and `value` for every other — a select being written by the slug of
      # its option, which is what the Enum column advertises.
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

      def refuse_too_many_targets(count)
        raise UnsupportedWriteError,
              "This write applies to #{count} #{name} records, more than the #{max_write_targets} one pass " \
              'covers: Pylon writes one record per request, against a budget of ten to twenty requests per ' \
              'minute, and a write stopping halfway would report a success it did not perform. Narrow the ' \
              'selection to reach the records past this point.'
      end

      # Named ids the collection cannot resolve exactly, the filter carrying
      # more than the ids themselves. How many of them the rest of the filter
      # matches is unknown here — it is what the read would answer — so the
      # count is reported as what it is, records named rather than records
      # written to.
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
