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
      Filter     = ForestAdminDatasourceToolkit::Components::Query::Filter
      Page       = ForestAdminDatasourceToolkit::Components::Query::Page
      Projection = ForestAdminDatasourceToolkit::Components::Query::Projection

      # How many records one filter-driven update or delete may reach. Pylon
      # writes one record per request against a budget of 10 to 20 requests per
      # minute, so a wider selection is refused rather than written halfway:
      # a delete that stopped in the middle of the page would look done and
      # would not be, which is the very thing this datasource refuses.
      MAX_WRITE_TARGETS = 20

      def create(_caller, data)
        serialize(create_record(build_payload(data, :create)))
      end

      def update(caller, filter, patch)
        ids = ids_for(caller, filter)
        return if ids.empty?

        payload = build_payload(patch, :update, caller: caller, filter: filter)
        return if payload.empty?

        ids.each { |id| update_record(id, payload) }
      end

      def delete(caller, filter)
        ids_for(caller, filter).each { |id| delete_record(id) }
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
        ids  = filtered_ids(tree)
        refuse_too_many_targets(ids.size) if ids && ids.size > max_write_targets
        return ids if ids && id_values(tree) && no_search?(filter)

        resolve_ids_by_list(caller, filter)
      end

      private

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
      # does not. What this answers is only "how many records is this write
      # about", which is the question the cap needs.
      def filtered_ids(node)
        return id_values(node) if id_values(node)
        return nil unless and_branch?(node)

        condition = Array(node.conditions).find { |child| id_values(child) }
        condition && id_values(condition)
      end

      # Keys the schema declares writable, custom fields included, in the shape
      # the endpoint takes. Everything else is dropped rather than refused: the
      # front sends the fields of its form, and a read-only one reaching the
      # payload is the agent's doing, not a request the operator made.
      def build_payload(data, direction, caller: nil, filter: nil)
        attrs = writable_attributes(data)
        attrs = honour_write_direction(attrs, direction, caller, filter)
        # Pylon fills in what a create leaves out; on an update a nil is the
        # operator clearing a value, so it travels.
        attrs = attrs.compact if direction == :create

        custom, native = split_custom_fields(attrs)
        payload = native.transform_keys { |field| payload_renames.fetch(field, field) }
        payload['custom_fields'] = custom unless custom.empty?
        payload
      end

      def writable_attributes(data)
        attrs = data.is_a?(Hash) ? data.transform_keys(&:to_s) : {}

        attrs.select { |field, _value| writable_column?(field) }
      end

      def writable_column?(field)
        column = schema[:fields][field]

        column&.type == 'Column' && !column.is_read_only
      end

      # A field of the other direction is dropped when it asks for nothing — no
      # value at all, or, on an update, the value the record already holds, which
      # is what a form resending an untouched field sends. It is refused when the
      # operator really changed it: Pylon cannot write it, and answering the edit
      # with a success it did not perform is worse than an error naming the
      # field.
      def honour_write_direction(attrs, direction, caller, filter)
        wrong = attrs.keys & (direction == :create ? update_only_fields : create_only_fields)
        return attrs if wrong.empty?

        stored = direction == :update ? stored_values(caller, filter, wrong) : []
        wrong.each do |field|
          value = attrs[field]
          next if value.nil? || value == ''
          next if direction == :update && stored.all? { |record| record[field] == value }

          refuse_wrong_direction(field, direction)
        end

        attrs.except(*wrong)
      end

      # Read only when a field of the wrong direction carries a value, and only
      # for that field: an update naming none costs no request at all.
      def stored_values(caller, filter, fields)
        list(caller, filter, Projection.new(['id'] + fields))
      end

      # Pylon reads its custom fields back as a map indexed by slug and writes
      # them as a list, one entry per field, carrying `values` for a multi-value
      # field and `value` for every other — a select being written by the slug of
      # its option, which is what the Enum column advertises.
      def split_custom_fields(attrs)
        by_column = custom_fields.to_h { |custom_field| [custom_field[:column_name], custom_field] }
        entries = []

        native = attrs.each_with_object({}) do |(field, value), rest|
          custom_field = by_column[field]
          custom_field ? entries << custom_field_entry(custom_field, value) : rest[field] = value
        end

        [entries, native]
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

      def refuse_wrong_direction(field, direction)
        detail = if direction == :create
                   'Pylon only accepts it on an existing record: create the record, then edit it.'
                 else
                   'Pylon only accepts it when the record is created, and exposes no endpoint to change it ' \
                     'afterwards.'
                 end

        raise UnsupportedWriteError, "'#{field}' cannot be set here on a #{name}: #{detail}"
      end

      def refuse_too_many_targets(count)
        raise UnsupportedWriteError,
              "This write applies to #{count} #{name} records, more than the #{max_write_targets} one pass " \
              'covers: Pylon writes one record per request, against a budget of ten to twenty requests per ' \
              'minute, and a write stopping halfway would report a success it did not perform. Narrow the ' \
              'selection to reach the records past this point.'
      end
    end
  end
end
