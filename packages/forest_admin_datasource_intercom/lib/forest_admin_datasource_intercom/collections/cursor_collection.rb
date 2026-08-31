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
    # * anything else is **refused**. Translating a Forest condition tree into
    #   Intercom's search DSL is lot 2, and until it exists a filter that cannot
    #   be honoured has to say so: an unfiltered page served in answer to a
    #   filter is the one failure this datasource is built to avoid.
    #
    # Counting is the exception that costs nothing: `total_count` is exact on
    # every response, filter included, so the record counter is one request.
    # Long by line count only: half of it is the refusals, and a refusal that
    # does not say what to do instead is a refusal an operator cannot act on.
    class CursorCollection < BaseCollection # rubocop:disable Metrics/ClassLength
      Aggregation = ForestAdminDatasourceToolkit::Components::Query::Aggregation

      # How many records an `id in [...]` read may fetch. One request per id --
      # Intercom has no "read these records" endpoint -- so the fan-out is
      # bounded rather than turned into a rate limit halfway through a page.
      MAX_ID_READS = 25

      # Countable, and exactly: unlike the pages a walk collected, `total_count`
      # is the whole dataset the filter names.
      def initialize(datasource, name)
        super
        enable_count
      end

      def list(_caller, filter, projection)
        warn_ignored_sort(filter&.sort)

        records = fetch_records(filter)
        rows = records.map { |record| project(serialize(record), projection) }
        enrich(records, rows, projection)
        rows
      end

      # Count only, and never a group: Intercom exposes no aggregate endpoint,
      # and grouping over the pages a walk happened to collect would look exact
      # while answering a fraction. Refused here rather than through the
      # contract's NotImplementedError, which reads as an oversight.
      def aggregate(_caller, filter, aggregation, _limit = nil)
        refuse_unsupported_aggregation!(aggregation)

        [{ 'group' => {}, 'value' => count_records(filter) }]
      end

      protected

      # The listing endpoint, its record key, and the parameters every read of
      # this collection carries.
      def list_endpoint = raise(NotImplementedError, "#{self.class} did not implement list_endpoint")
      def record_endpoint = list_endpoint
      def list_key = 'data'
      def read_params = {}

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
      def read_page(per_page:, cursor:)
        client.list_page(list_endpoint, per_page: [per_page, max_page_size].min,
                                        starting_after: cursor, params: read_params, list_key: list_key)
      end

      # A column of this tier advertises no filter and no sort, because the
      # collection can honour neither -- except on the primary key, which is
      # answered by the record endpoint rather than by a filter. A schema that
      # advertised more would put filters in the interface that the read then
      # refuses.
      def add_column(name, type, is_primary_key: false)
        operators = is_primary_key ? [Operators::EQUAL, Operators::IN] : []
        add_field(name, ColumnSchema.new(column_type: type,
                                         filter_operators: operators,
                                         is_primary_key: is_primary_key,
                                         is_sortable: false,
                                         is_groupable: false))
      end

      def walker
        @walker ||= Pagination::CursorWalker.new
      end

      private

      def fetch_records(filter)
        ids = id_lookup(filter)
        return records_by_ids(ids) if ids

        refuse_filter!(filter) unless browsing?(filter)

        listed_records(filter)
      end

      def browsing?(filter)
        filter.nil? || (filter.condition_tree.nil? && blank_search?(filter))
      end

      def blank_search?(filter)
        search = filter.respond_to?(:search) ? filter.search : nil
        search.nil? || search.to_s.strip.empty?
      end

      # A record detail is `id equals X`, and a bulk read of related records is
      # `id in [...]`. Only a bare leaf on the primary key takes this route: an
      # `and` also carrying a scope names a narrower set than the ids do, and
      # answering it with the ids alone would serve records the scope excludes.
      def id_lookup(filter)
        tree = filter&.condition_tree
        return nil unless tree.is_a?(Leaf) && tree.field.to_s == primary_key
        return nil unless blank_search?(filter)

        case tree.operator
        when Operators::EQUAL then [tree.value].compact.map(&:to_s)
        when Operators::IN then Array(tree.value).compact.map(&:to_s)
        end
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
          client.fetch_record(record_endpoint, id, params: read_params)
        rescue APIError => e
          raise unless e.status == 404

          nil
        end
      end

      def listed_records(filter)
        offset, limit = translate_page(filter&.page)

        walker.walk(offset: offset, limit: limit) { |per_page, cursor| read_page(per_page: per_page, cursor: cursor) }
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
      def count_records(filter)
        ids = id_lookup(filter)
        return records_by_ids(ids).size if ids

        refuse_filter!(filter) unless browsing?(filter)

        page = read_page(per_page: 1, cursor: nil)
        return page.total_count if page.total_count

        raise UnsupportedOperatorError,
              "#{name} cannot be counted: Intercom answered this listing without a total_count, and counting the " \
              'pages the agent walked would answer a fraction of the collection as if it were the whole of it.'
      end

      def refuse_unsupported_aggregation!(aggregation)
        return if aggregation.is_a?(Aggregation) && aggregation.operation.to_s.casecmp('count').zero? &&
                  Array(aggregation.groups).empty? && aggregation.field.nil?

        raise UnsupportedOperatorError,
              "#{name} can only be counted: Intercom exposes no aggregate endpoint, and grouping or summing the " \
              'pages the agent walked would answer a fraction of the collection as if it were the whole of it. ' \
              'Chart it on a collection read whole, or wait for the bounded group-by of the reporting lot.'
      end

      def refuse_filter!(filter)
        detail = if filter&.condition_tree
                   'a condition on this collection'
                 else
                   'a free-text search'
                 end

        raise UnsupportedOperatorError,
              "#{name} cannot answer #{detail} yet: it reads Intercom's listing endpoint, which takes no filter. " \
              'Server-side filtering goes through the search endpoint and arrives with the filter translation. ' \
              'Until then, remove the condition, the scope or the segment carrying it rather than being served a ' \
              'page that would look filtered without being it.'
      end

      # Intercom accepts a `sort` on these endpoints and ignores it without a
      # word -- measured -- so an order the operator asked for and did not get
      # has to be reported here or nowhere. The ascending primary-key sort the
      # agent injects when a request names none is not one of those.
      def warn_ignored_sort(sort)
        clauses = Array(sort)
        return if clauses.empty? || default_pk_sort?(clauses)

        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] #{name} was asked to sort on " \
          "#{clauses.map { |clause| clause[:field] || clause["field"] }.join(", ")}, and Intercom ignores a sort on " \
          'this endpoint without reporting it. The rows come back in the order the API imposes.'
        )
      end

      def default_pk_sort?(clauses)
        clauses.size == 1 &&
          (clauses.first[:field] || clauses.first['field']).to_s == primary_key &&
          (clauses.first[:ascending] || clauses.first['ascending']) != false
      end

      def warn_truncated_ids(asked)
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] #{name} was asked for #{asked} records by id and read the first " \
          "#{MAX_ID_READS}: Intercom reads them one request each. The result is truncated."
        )
      end
    end
  end
end
