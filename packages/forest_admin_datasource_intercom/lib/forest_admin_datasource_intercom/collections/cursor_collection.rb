module ForestAdminDatasourceIntercom
  module Collections
    # Base for the collections Intercom paginates by cursor: conversations and
    # tickets. The opposite tier of `FetchAllCollection` in every way -- what is
    # in hand is a page of something far larger, so nothing may be filtered,
    # sorted or counted in memory without answering a fraction as if it were the
    # whole.
    #
    # Three routes, and no fourth:
    #
    # * no condition at all -- a list view -- walks the listing endpoint;
    # * `id equals X` reads the record through its own endpoint, which is what a
    #   record detail is;
    # * anything else is translated into Intercom's search DSL and walked
    #   through the search endpoint. What the translator will not express, it
    #   refuses by name: an unfiltered page served in answer to a filter is the
    #   one failure this datasource is built to avoid.
    #
    # A condition through a relation is resolved before any of that: the target
    # collection is asked which of its records match, and what reaches Intercom
    # is a condition on the foreign key. See `Relations`.
    #
    # Counting is the exception that costs nothing: `total_count` is exact on
    # every response, filter included, so the record counter is one request.
    # Long by line count only: half of it is the refusals, and a refusal that
    # does not say what to do instead is a refusal an operator cannot act on.
    class CursorCollection < BaseCollection # rubocop:disable Metrics/ClassLength
      include RecordsById

      # Countable, and exactly: unlike the pages a walk collected, `total_count`
      # is the whole dataset the filter names.
      def initialize(datasource, name)
        super
        enable_count
      end

      # One request per id here, so a relation pointing at this tier resolves a
      # slice at a time and is refused past what a slice may hold -- see
      # `Relations#target_rows`. The collection that reads its ids in bulk
      # widens both; see `Contact`.
      def ids_per_read = max_id_reads
      def max_resolvable_ids = max_id_reads

      def list(caller, filter, projection)
        records = fetch_records(caller, filter, server_sort(filter))
        # Serialized whole and projected afterwards rather than the other way
        # round: a projection reaching through a relation names no foreign key,
        # and the key is where the relation is read from.
        serialized = records.map { |record| serialize(record) }
        rows = serialized.map { |record| project(record, projection) }

        enrich(records, rows, projection)
        embed_relations(caller, serialized, rows, projection)
        rows
      end

      # Count only, and never a group: Intercom exposes no aggregate endpoint,
      # and grouping over the pages a walk happened to collect would look exact
      # while answering a fraction. Refused here rather than through the
      # contract's NotImplementedError, which reads as an oversight.
      def aggregate(caller, filter, aggregation, _limit = nil)
        refuse_unsupported_aggregation!(aggregation)

        [{ 'group' => {}, 'value' => count_records(caller, filter) }]
      end

      protected

      # The listing endpoint, its record key, and the parameters every read of
      # this collection carries.
      def list_endpoint = raise(NotImplementedError, "#{self.class} did not implement list_endpoint")
      def record_endpoint = list_endpoint
      def list_key = 'data'
      def read_params = {}

      # The row of the measured table this collection is filtered through: what
      # its columns may advertise, and what the translator is allowed to write.
      def searchable = raise(NotImplementedError, "#{self.class} did not implement searchable")

      def search_endpoint
        @search_endpoint ||= Query::SearchFields.fetch(searchable)
      end

      # The column a free-text search is answered on, for a collection whose
      # endpoint has one. Nil elsewhere, and a search is then refused rather than
      # answered by a page that ignored it.
      def search_column = nil

      # One Intercom entity flattened into a record matching the schema.
      def serialize(_entity) = raise(NotImplementedError, "#{self.class} did not implement serialize")

      # Hook for what a row needs beyond its own payload. Left empty here: what
      # it costs is the collection's business, not this base's.
      def enrich(_records, _rows, _projection); end

      # Bounded per collection rather than by the API maximum: Intercom offers no
      # field selection, so a collection whose rows carry their whole timeline
      # pays for it by the page. See Ticket.
      def max_page_size = Client::MAX_PER_PAGE

      # One page of the collection. A listing for conversations, a search for
      # tickets -- Intercom exposes no `GET /tickets` at all -- so the endpoint
      # and its shape belong to the collection, while walking it does not.
      def read_page(per_page:, cursor:, query: nil, sort: nil)
        size = [per_page, max_page_size].min
        # The listing endpoint neither filters nor sorts, and a collection whose
        # records are only reachable through the search has no listing at all.
        # Either way what routes the read to the search is a query, so the one
        # that matches everything stands in for the condition there is none of.
        query ||= match_all_query if sort || searchable_only?

        if query.nil?
          client.list_page(list_endpoint, per_page: size, starting_after: cursor,
                                          params: read_params, list_key: list_key)
        else
          client.search_page(search_endpoint.path, query: query, per_page: size, starting_after: cursor,
                                                   params: read_params, list_key: list_key, sort: sort)
        end
      end

      # A column advertises exactly the filters the search endpoint answers on
      # it, taken from the measured table and derived by the operator table --
      # never written by hand here, so a column cannot offer a filter the
      # translator would refuse. A column the table does not carry advertises
      # none, which is how a refusal is spelled in a schema.
      #
      # The primary key is the exception, and it is not a filter: `id equals X`
      # and `id in [...]` are answered by the record endpoint.
      #
      # A column is sortable only where the measured table says the endpoint
      # sorts, which is `/contacts/search` and nowhere else: the other two
      # accept a `sort` and ignore it without a word, so a sortable column there
      # would promise an order that never happens.
      def add_column(name, type, is_primary_key: false)
        add_field(name, ColumnSchema.new(column_type: type,
                                         filter_operators: column_operators(name, is_primary_key),
                                         is_primary_key: is_primary_key,
                                         is_read_only: true,
                                         is_sortable: sortable_column?(name),
                                         is_groupable: false))
      end

      def sortable_column?(name)
        search_endpoint.field(name)&.sortable? == true
      end

      # The Intercom query standing in for the condition a read has none of.
      # Two collections need one and for different reasons: Intercom exposes no
      # `GET /tickets` at all, and an order is applied by the search endpoint
      # alone. Nil where the listing endpoint answers both, which is where a
      # sort is reported as ignored rather than dropped.
      def match_all_query = nil

      # Whether every read of this collection goes through the search, listing
      # or not.
      def searchable_only? = false

      # Bounded, unlike the tier read whole: one more than a group may hold is
      # all it takes to know the fan-out will not fit, and reading further would
      # walk a whole collection to refuse it afterwards.
      def match_page
        ForestAdminDatasourceToolkit::Components::Query::Page.new(
          offset: 0, limit: Query::ConditionTreeTranslator::MAX_GROUP_SIZE + 1
        )
      end

      def walker
        @walker ||= Pagination::CursorWalker.new
      end

      # How many records a bulk read by id may fetch. A hook rather than the
      # constant, since the collection that reads its ids in bulk answers far
      # more of them for the same request count.
      def max_id_reads = MAX_ID_READS

      private

      def column_operators(name, is_primary_key)
        return [Operators::EQUAL, Operators::IN] if is_primary_key

        field = search_endpoint.field(name)

        field ? Query::OperatorTable.forest_operators(field) : []
      end

      def fetch_records(caller, filter, sort = nil)
        ids = id_lookup(filter)
        # The window is cut out of the ids rather than out of the records they
        # read: Intercom reads them one request each, so paging after the read
        # would pay for a whole page to hand back a slice of it -- and page 2 of
        # a set larger than the cap would come back empty, the records it names
        # having been dropped by the truncation before the window was applied.
        if ids
          # Which is also why an order cannot be honoured on this route: the
          # window is cut in the order the ids were named, so sorting what comes
          # back would order a slice picked by something else. Reported rather
          # than dropped in silence, like every other order this tier cannot
          # apply -- `server_sort` stayed quiet, having found a column Intercom
          # does sort.
          warn_unordered_ids(sort) if sort
          return records_by_ids(page_window(ids, filter))
        end

        query = translate(caller, filter)
        # A condition through a relation the target matched no record with names
        # no row, and Intercom's DSL cannot say so: the read is skipped rather
        # than sent as a filter that would come back with everything.
        return [] if query == NOTHING

        listed_records(filter, query, sort)
      end

      # The Intercom query a filter comes down to, or nil for a list view, which
      # walks the listing endpoint instead. The free-text search is folded into
      # the condition tree rather than added to the translated query: written as
      # one tree, it is checked against the nesting Intercom allows like every
      # other condition, instead of adding a level nothing counted.
      def translate(caller, filter)
        tree = rewrite_relation_conditions(caller, combined_tree(filter)) do |key, ids, leaf|
          relation_group(key, ids, leaf)
        end
        return NOTHING if tree == NOTHING

        Query::ConditionTreeTranslator.call(tree, endpoint: search_endpoint, collection: name,
                                                  timezone: timezone_for(caller),
                                                  attribute_columns: attribute_column_names)
      end

      # The ids the target matched, written as the filter Intercom does take on
      # the foreign key: a group of equalities, its DSL offering no membership
      # operator on these fields.
      #
      # That group counts against the fifteen conditions Intercom allows, so a
      # relation condition matching more records than that is refused rather than
      # sent -- and refused here, where the message can name the relation the
      # operator filtered on rather than the key it resolved to.
      #
      # It also costs a level of nesting, which is why it is built as the group
      # `Relations` can tell from one the operator wrote: inlined into a parent
      # that aggregates the same way, it costs none.
      def relation_group(key, ids, leaf)
        refuse_fan_out!(leaf, key, ids) if ids.size > Query::ConditionTreeTranslator::MAX_GROUP_SIZE
        return Leaf.new(key, Operators::EQUAL, ids.first) if ids.size == 1

        RelationBranch.new('Or', ids.map { |id| Leaf.new(key, Operators::EQUAL, id) }, leaf.field)
      end

      # Inlining a relation group into its parent trades a level of nesting for
      # width, and Intercom bounds both. Past the conditions a group may hold,
      # the nested form is the one it answers.
      def absorb_relation_group?(size)
        size <= Query::ConditionTreeTranslator::MAX_GROUP_SIZE
      end

      # A relation this endpoint filters nothing through. It is navigable all the
      # same -- the read costs nothing, the target being read whole -- and saying
      # which of the two it is, is the whole point of the message.
      def check_relation_filterable!(leaf, relation)
        key = relation.foreign_key
        refuse_unfilterable_key!(leaf, key) if search_endpoint.field(key).nil?
      end

      def refuse_unfilterable_key!(leaf, key)
        raise UnsupportedOperatorError,
              "#{name} cannot filter #{leaf.field.inspect}: the relation resolves to #{key.inspect}, on " \
              "which #{search_endpoint.path} takes no filter. The relation is there to be read and " \
              "navigated; filter on one of: #{search_endpoint.filterable_columns.join(", ")}."
      end

      def refuse_fan_out!(leaf, key, _ids)
        # "more than", never a count: the target is read one record past what a
        # group may hold, so what is known is that it does not fit -- printing
        # 16 where a workspace holds three thousand would read as a number the
        # operator could go and narrow by one.
        raise UnsupportedOperatorError,
              "#{name} cannot filter #{leaf.field.inspect}: it names more than " \
              "#{Query::ConditionTreeTranslator::MAX_GROUP_SIZE} records, " \
              "#{search_endpoint.path} answers #{key.inspect} one value at a time, and Intercom takes " \
              "#{Query::ConditionTreeTranslator::MAX_GROUP_SIZE} conditions per group. Narrow the condition " \
              "on the relation, or filter on #{key.inspect} itself."
      end

      def combined_tree(filter)
        conditions = [filter&.condition_tree, search_condition(filter)].compact
        return conditions.first if conditions.size < 2

        ForestAdminDatasourceToolkit::Components::Query::ConditionTree::ConditionTreeFactory.intersect(conditions)
      end

      # A free-text search reaches Intercom as a condition on the one column its
      # endpoint matches text on -- per word, not as a substring, which the
      # README says rather than the interface implying otherwise.
      def search_condition(filter)
        return nil if blank_search?(filter)

        refuse_search! if search_column.nil?

        Leaf.new(search_column, Operators::CONTAINS, filter.search.to_s.strip)
      end

      # The records of this tier carry bodies written by end customers, so every
      # read of one asks Intercom for plain text (R10). `BaseCollection` reads
      # this on the way to the record endpoint.
      def record_read_params = read_params

      def listed_records(filter, query, sort = nil)
        offset, limit = translate_page(filter&.page)

        walker.walk(offset: offset, limit: limit) do |per_page, cursor|
          read_page(per_page: per_page, cursor: cursor, query: query, sort: sort)
        end
      end

      # A filter with no page asks for every record it matched; the walker reads
      # that as the nil limit it bounds with its own caps.
      def translate_page(page)
        return [0, nil] if page.nil?

        limit = page.limit.to_i
        [page.offset.to_i.clamp(0, nil), limit.positive? ? limit : nil]
      end

      # Exact, and one request: `total_count` counts what the filter names, not
      # what a page happened to hold. An id lookup counts the records it found,
      # which is cheaper still.
      def count_records(caller, filter)
        ids = id_lookup(filter)
        return count_by_ids(ids) if ids

        query = translate(caller, filter)
        return 0 if query == NOTHING

        exact_count(read_page(per_page: 1, cursor: nil, query: query))
      end

      def refuse_search!
        raise UnsupportedOperatorError,
              "#{name} cannot answer a free-text search: #{search_endpoint.path} matches values field by field, " \
              'and this collection exposes no text column it searches. Filter on a column instead of searching.'
      end

      # The order Intercom will really apply, written the way the client sends
      # it -- or nil, and the order the operator asked for is then reported
      # rather than dropped in silence.
      #
      # The ascending primary-key sort the agent injects when a request names
      # none is neither honoured nor reported: it is not an order anybody asked
      # for, and `/contacts/search` does not sort on an id anyway.
      def server_sort(filter)
        clauses = Array(filter&.sort)
        return nil if clauses.empty? || default_pk_sort?(clauses)

        honoured = honourable_sort(clauses)
        warn_ignored_sort(clauses) if honoured.nil?
        honoured
      end

      # One clause, on a column the measured table says the endpoint sorts.
      # Intercom takes a single `{ field, order }` and nothing composite, so a
      # second clause is not half-honoured: honouring the first alone would
      # order the page by something the operator did not ask for.
      def honourable_sort(clauses)
        return nil unless clauses.size == 1

        clause = clauses.first
        field = search_endpoint.field(sort_field(clause).to_s)
        return nil unless field&.sortable?

        { field: field.field, ascending: ascending?(clause) }
      end

      # Intercom accepts a `sort` on the other two endpoints and ignores it
      # without a word -- measured -- so an order asked for and not applied has
      # to be reported here or nowhere.
      def warn_ignored_sort(clauses)
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] #{name} was asked to sort on " \
          "#{clauses.map { |clause| sort_field(clause) }.join(", ")}, which Intercom does not sort this " \
          'collection on -- and it ignores a sort it refuses without reporting it. The rows come back in the ' \
          'order the API imposes.'
        )
      end

      # `sort` here is the clause `server_sort` found the endpoint does honour,
      # which is why nothing has reported it yet: it is this route, not the
      # column, that cannot carry it.
      def warn_unordered_ids(sort)
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] #{name} was asked to sort on #{sort[:field].inspect} while reading " \
          'records by id, which Intercom reads by id and in no order. The rows come back in the order the ids ' \
          'were named.'
        )
      end
    end
  end
end
