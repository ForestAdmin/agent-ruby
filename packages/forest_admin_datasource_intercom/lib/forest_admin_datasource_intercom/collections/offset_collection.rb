module ForestAdminDatasourceIntercom
  module Collections
    # The third pagination tier, and the only one that maps onto what Forest
    # asks for without translating anything: Intercom paginates
    # `POST /companies/list` by **offset**, so page 7 of a list view is one
    # request rather than six pages walked to reach it. No cursor walker, no
    # cap, and no truncation warning.
    #
    # What it pays for that is filtering. There is no search endpoint for
    # companies at all -- `GET /companies/scroll` exists and is deliberately
    # rejected, one open scroll per app expiring in a minute cannot serve
    # concurrent list views -- so what a filter may say is four exact lookups
    # and nothing else. Everything past them is **refused by name**, the rule
    # the cursor tier already set: a page served in answer to a filter it
    # ignored is the one failure this datasource is built to avoid.
    #
    # In memory it does nothing: no filter, no sort, no group. What is in hand
    # is a page of something larger, exactly like the cursor tier, and the same
    # reasoning applies.
    # Long by line count only: half of it is the refusals, and a refusal that
    # does not say what to do instead is one an operator cannot act on.
    class OffsetCollection < BaseCollection # rubocop:disable Metrics/ClassLength
      include RecordsById

      # What one page holds when the read names no window: a relation resolving
      # its target, a segment, a customizer. A list view always names one.
      UNBOUNDED_PAGE_SIZE = Client::MAX_PER_PAGE

      # And how many such pages are read before the answer is cut short. The
      # figure only ever applies to a read with no window of its own.
      MAX_COLLECTED_PAGES = 10

      # What a read that *does* name a window may collect before it is cut
      # short. A window is its own bound, so the page count above must not apply
      # to it: a window needing eleven pages would come back one page short
      # while the warning blamed it for naming no window -- which it did name.
      # This is the backstop for a window nothing sane asked for, and it is the
      # cursor walker's own record budget, that tier being bounded the same way.
      MAX_COLLECTED_RECORDS = Pagination::CursorWalker::MAX_RECORDS

      # How many records of this collection one relation read may resolve.
      # Higher than `MAX_ID_READS`, which bounds a single request batch, and
      # deliberately above every page size a list view offers: a page naming one
      # account per row resolves, and a read naming more -- an export, a
      # segment resolved whole -- is refused by name rather than answered with
      # a nil where an account exists. There is no bulk read for a company, so
      # each one costs a request and the figure is what an operator waits for.
      MAX_RELATION_READS = 100

      def initialize(datasource, name)
        super
        enable_count
      end

      def ids_per_read = MAX_ID_READS
      def max_resolvable_ids = MAX_RELATION_READS

      def list(caller, filter, projection)
        warn_ignored_sort(filter&.sort)

        records = fetch_records(filter)
        serialized = records.map { |record| serialize(record) }
        rows = serialized.map { |record| project(record, projection) }

        embed_relations(caller, serialized, rows, projection)
        rows
      end

      # Count only, and never a group: `total_count` is exact on every listing,
      # while grouping the page in hand would answer a fraction as if it were
      # the whole.
      def aggregate(_caller, filter, aggregation, _limit = nil)
        refuse_unsupported_aggregation!(aggregation)

        [{ 'group' => {}, 'value' => count_records(filter) }]
      end

      protected

      # The endpoint that lists the collection by offset, the one that reads a
      # record, and the lookups Intercom answers on the listing path.
      def list_path = raise(NotImplementedError, "#{self.class} did not implement list_path")
      def record_endpoint = raise(NotImplementedError, "#{self.class} did not implement record_endpoint")
      def lookup_path = record_endpoint
      def lookups = {}

      def serialize(_entity) = raise(NotImplementedError, "#{self.class} did not implement serialize")

      # A column advertises a filter only where Intercom looks the collection up
      # by it, so a column cannot offer a filter this tier would then refuse.
      # The primary key is the exception and it is not a filter: `id equals X`
      # and `id in [...]` are answered by the record endpoint.
      #
      # Nothing is sortable: the listing takes no order and ordering a page in
      # hand would order a fraction of the collection.
      def add_column(name, type, is_primary_key: false)
        add_field(name, ColumnSchema.new(column_type: type,
                                         filter_operators: column_operators(name, is_primary_key),
                                         is_primary_key: is_primary_key,
                                         is_read_only: true,
                                         is_sortable: false,
                                         is_groupable: false))
      end

      private

      def column_operators(name, is_primary_key)
        return [Operators::EQUAL, Operators::IN] if is_primary_key

        lookups.key?(name) ? [Operators::EQUAL] : []
      end

      def fetch_records(filter)
        ids = id_lookup(filter)
        return records_by_ids(page_window(ids, filter)) if ids

        lookup = lookup_condition(filter)
        return page_window(looked_up_records(lookup), filter) if lookup

        refuse_condition!(filter.condition_tree) unless filter&.condition_tree.nil?

        listed_records(filter)
      end

      def count_records(filter)
        ids = id_lookup(filter)
        return count_by_ids(ids) if ids

        lookup = lookup_condition(filter)
        return looked_up_records(lookup).size if lookup

        refuse_condition!(filter.condition_tree) unless filter&.condition_tree.nil?

        exact_count(read_offset_page(page: 1, per_page: 1))
      end

      # The window a list view asked for, read as the page Intercom counts from
      # 1. An offset that does not fall on a page boundary is served by reading
      # the page it lands in and the ones after it until the window is filled --
      # exactly, rather than by rounding the offset to something the API likes.
      def listed_records(filter)
        offset, limit = window(filter&.page)
        per_page = Client.bounded_per_page(limit || UNBOUNDED_PAGE_SIZE)
        skip = offset % per_page

        collected = collect_pages(first_page: (offset / per_page) + 1, per_page: per_page,
                                  wanted: limit && (skip + limit))

        limit ? (collected[skip, limit] || []) : collected.drop(skip)
      end

      def collect_pages(first_page:, per_page:, wanted:)
        records = []
        page = first_page
        read = 0

        loop do
          answer = read_offset_page(page: page, per_page: per_page)
          records.concat(answer.records)
          read += 1
          break if last_page?(answer, page) || (wanted && records.size >= wanted)
          break if cap_reached?(read, records.size, wanted)

          page += 1
        end

        records
      end

      def read_offset_page(page:, per_page:)
        client.offset_page(list_path, page: page, per_page: per_page)
      end

      def last_page?(answer, page)
        answer.records.empty? || (answer.total_pages && page >= answer.total_pages)
      end

      # Which of the two caps applies, and the reason that goes with it: a read
      # with no window of its own is stopped by the page count, a read that
      # named one by the record budget. Telling a list view it named no window
      # is exactly the confusion these two keep apart.
      def cap_reached?(read, collected, wanted)
        if wanted
          return false if collected < MAX_COLLECTED_RECORDS

          warn_capped("#{collected} record(s)",
                      'this read named a window larger than one answer may hold')
        else
          return false if read < MAX_COLLECTED_PAGES

          warn_capped("#{read} page(s) / #{collected} record(s)",
                      'this read named no window of its own, and a list view always does')
        end

        true
      end

      def warn_capped(reached, reason)
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] Stopped reading #{name} after #{reached}; the rest is left out: " \
          "#{reason}."
        )
      end

      # A filter with no page asks for every record it matched; nil is how the
      # window says so.
      def window(page)
        return [0, nil] if page.nil?

        limit = page.limit.to_i
        [page.offset.to_i.clamp(0, nil), limit.positive? ? limit : nil]
      end

      def lookup_condition(filter)
        tree = filter&.condition_tree
        return nil unless tree.is_a?(Leaf) && tree.operator == Operators::EQUAL

        parameter = lookups[tree.field.to_s]
        parameter && { parameter => tree.value.to_s }
      end

      # An exact lookup answers few records -- one, for the keys this publishes
      # -- so it is read as a single page. More than that page holds is reported
      # rather than dropped in silence.
      #
      # A lookup naming no record is an empty page, not a failure: Intercom
      # answers this route with a 404 where a search endpoint would answer an
      # empty list, and a filter matching nothing is the most ordinary thing a
      # list view does. Read the way a record read by its id already is.
      def looked_up_records(params)
        answer = client.lookup_page(lookup_path, params: params)
        warn_truncated_lookup(params) if answer.next_cursor

        answer.records
      rescue APIError => e
        raise unless e.status == 404

        []
      end

      def refuse_condition!(tree)
        offender = nil
        tree.some_leaf { |leaf| offender = leaf }

        raise UnsupportedOperatorError,
              "#{name} cannot filter #{(offender&.field).inspect}: Intercom exposes no search endpoint for this " \
              "collection and looks a record up by #{lookups.keys.join(", ")} alone -- one exact value at a time, " \
              'with no combination and no other operator. Filter on one of those, or reach the record from the ' \
              'collection next door.'
      end

      # Intercom takes no order on this listing at all -- there is no parameter
      # for one -- so an order asked for and not applied is reported here or
      # nowhere. The ascending primary-key sort the agent injects when a request
      # names none is not one of those.
      def warn_ignored_sort(sort)
        clauses = Array(sort)
        return if clauses.empty? || default_pk_sort?(clauses)

        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] #{name} was asked to sort on " \
          "#{clauses.map { |clause| sort_field(clause) }.join(", ")}, and Intercom takes no order " \
          'on this listing. The rows come back in the order the API imposes.'
        )
      end

      def warn_truncated_lookup(params)
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] #{name} looked up #{params.inspect} and Intercom advertised more " \
          'records than one page holds; the rest is left out. This lookup is meant for a key that names one record.'
        )
      end
    end
  end
end
