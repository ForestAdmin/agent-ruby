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
      Aggregation = ForestAdminDatasourceToolkit::Components::Query::Aggregation

      # How many records an `id in [...]` read may fetch. One request per id --
      # Intercom has no "read these records" endpoint here either -- so the
      # fan-out is bounded rather than turned into a rate limit halfway through
      # a page.
      MAX_ID_READS = 25

      # What one page holds when the read names no window: a relation resolving
      # its target, a segment, a customizer. A list view always names one.
      UNBOUNDED_PAGE_SIZE = Client::MAX_PER_PAGE

      # And how many such pages are read before the answer is cut short. The
      # figure only ever applies to a read with no window of its own.
      MAX_COLLECTED_PAGES = 10

      def initialize(datasource, name)
        super
        enable_count
      end

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
        return records_by_ids(ids).size if ids

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
          break if cap_reached?(read, records.size)

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

      def cap_reached?(read, collected)
        return false if read < MAX_COLLECTED_PAGES

        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] Stopped reading #{name} after #{read} page(s) / #{collected} " \
          'record(s); the rest is left out. This read named no window of its own, and a list view always does.'
        )
        true
      end

      # A filter with no page asks for every record it matched; nil is how the
      # window says so.
      def window(page)
        return [0, nil] if page.nil?

        limit = page.limit.to_i
        [page.offset.to_i.clamp(0, nil), limit.positive? ? limit : nil]
      end

      # A record detail is `id equals X`, and a bulk read of related records is
      # `id in [...]`. Only a bare leaf on the primary key takes this route: an
      # `and` also carrying a scope names a narrower set than the ids do.
      def id_lookup(filter)
        tree = filter&.condition_tree
        return nil unless tree.is_a?(Leaf) && tree.field.to_s == primary_key

        case tree.operator
        when Operators::EQUAL then [tree.value].compact.map(&:to_s)
        when Operators::IN then Array(tree.value).compact.map(&:to_s)
        end
      end

      def lookup_condition(filter)
        tree = filter&.condition_tree
        return nil unless tree.is_a?(Leaf) && tree.operator == Operators::EQUAL

        parameter = lookups[tree.field.to_s]
        parameter && { parameter => tree.value.to_s }
      end

      def primary_key
        @primary_key ||= fields.find do |_name, field|
          field.respond_to?(:is_primary_key) && field.is_primary_key
        end&.first
      end

      # A record the operator can no longer reach -- deleted, or outside the
      # token's scope -- reads as "no record" rather than as a failed page.
      def records_by_ids(ids)
        wanted = ids.first(MAX_ID_READS)
        warn_truncated_ids(ids.size) if ids.size > wanted.size

        wanted.filter_map do |id|
          client.fetch_record(record_endpoint, id)
        rescue APIError => e
          raise unless e.status == 404

          nil
        end
      end

      # An exact lookup answers few records -- one, for the keys this publishes
      # -- so it is read as a single page. More than that page holds is reported
      # rather than dropped in silence.
      def looked_up_records(params)
        answer = client.lookup_page(lookup_path, params: params)
        warn_truncated_lookup(params) if answer.next_cursor

        answer.records
      end

      def exact_count(page)
        return page.total_count if page.total_count

        raise UnsupportedOperatorError,
              "#{name} cannot be counted: Intercom answered this listing without a total_count, and counting the " \
              'pages the agent read would answer a fraction of the collection as if it were the whole of it.'
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

      def refuse_unsupported_aggregation!(aggregation)
        return if aggregation.is_a?(Aggregation) && aggregation.operation.to_s.casecmp('count').zero? &&
                  Array(aggregation.groups).empty? && aggregation.field.nil?

        raise UnsupportedOperatorError,
              "#{name} can only be counted: Intercom exposes no aggregate endpoint, and grouping or summing the " \
              'pages the agent read would answer a fraction of the collection as if it were the whole of it.'
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
          "#{clauses.map { |clause| clause[:field] || clause["field"] }.join(", ")}, and Intercom takes no order " \
          'on this listing. The rows come back in the order the API imposes.'
        )
      end

      def default_pk_sort?(clauses)
        return false unless clauses.size == 1

        clause = clauses.first
        return false unless (clause[:field] || clause['field']).to_s == primary_key

        ascending = clause.key?(:ascending) ? clause[:ascending] : clause['ascending']
        ascending != false
      end

      def warn_truncated_ids(asked)
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] #{name} was asked for #{asked} records by id and read the first " \
          "#{MAX_ID_READS}: Intercom reads them one request each. The result is truncated."
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
