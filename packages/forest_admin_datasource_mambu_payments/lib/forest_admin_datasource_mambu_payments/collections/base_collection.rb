module ForestAdminDatasourceMambuPayments
  module Collections
    # Shared behaviour for every Numeral-backed collection.
    #
    # Subclasses declare their REST resource once with `client_resource` and
    # implement `serialize`. The read path (list / count / id-lookup /
    # pagination / relation embedding) lives here so a fix lands in one place
    # rather than being copy-pasted across ~17 collections.
    #
    # Filtering contract: `collection_filters` lists the server-filterable
    # fields (merged with the always-present `id`). `reconcile_filter_operators!`
    # then narrows each column's advertised `filter_operators` to exactly what
    # the Numeral API can serve, so the UI never offers a filter that would
    # raise at query time.
    # rubocop:disable Metrics/ClassLength
    class BaseCollection < ForestAdminDatasourceToolkit::Collection
      ColumnSchema   = ForestAdminDatasourceToolkit::Schema::ColumnSchema
      Operators      = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
      Leaf           = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
      ForestException = ForestAdminDatasourceToolkit::Exceptions::ForestException

      STRING_OPS = [Operators::EQUAL, Operators::NOT_EQUAL, Operators::IN, Operators::NOT_IN,
                    Operators::PRESENT, Operators::BLANK].freeze
      NUMBER_OPS = (STRING_OPS + [Operators::GREATER_THAN, Operators::LESS_THAN]).freeze
      DATE_OPS   = [Operators::EQUAL, Operators::BEFORE, Operators::AFTER,
                    Operators::PRESENT, Operators::BLANK].freeze
      BOOL_OPS   = [Operators::EQUAL, Operators::NOT_EQUAL,
                    Operators::PRESENT, Operators::BLANK].freeze

      # The id column is addressable (detail views, record selection) but the
      # Numeral list endpoints have NO `id`/`ids` filter, so it is served by the
      # find-by-id short-circuit (extract_id_lookup) and deliberately kept OUT of
      # api_filters — a combined `id AND <field>` predicate raises loudly rather
      # than silently sending an ignored param.
      ID_OPS = [Operators::EQUAL, Operators::IN].freeze

      class << self
        attr_accessor :resource_singular, :resource_plural
      end

      # Declares the Numeral REST resource backing this collection, wiring the
      # generic read path to the matching `list_*` / `count_*` / `find_*`
      # client methods.
      def self.client_resource(singular, plural = nil)
        self.resource_singular = singular.to_s
        self.resource_plural = (plural || "#{singular}s").to_s
      end

      def list(_caller, filter, projection)
        records = fetch_records(filter)
        rows = records.map { |r| project(serialize(r), projection) }
        embed_relations(rows, records, projection)
        rows
      end

      def aggregate(_caller, filter, aggregation, _limit = nil)
        unless aggregation.operation == 'Count' && aggregation.field.nil? && aggregation.groups.empty?
          raise ForestException, 'Mambu Payments datasource only supports Count aggregation without groups.'
        end

        [{ 'value' => count_records(filter), 'group' => {} }]
      end

      protected

      # Server-filterable fields the Numeral API accepts. Subclasses override
      # `collection_filters` with entries like:
      #   { 'connected_account_id' => { ops: [Operators::EQUAL, Operators::IN] } }
      # Anything not declared raises UnsupportedOperatorError when filtered on,
      # so we never silently return unfiltered results. `id` is intentionally
      # absent — see ID_OPS.
      def api_filters
        collection_filters
      end

      def collection_filters
        {}
      end

      # ManyToOne relations to embed during `list`. Subclasses override with
      # entries like:
      #   { foreign_key: 'connected_account_id', relation_name: 'connected_account',
      #     collection: 'MambuConnectedAccount' }
      def many_to_one_embeds
        []
      end

      # Aligns each column's advertised operators with what we can actually
      # serve: the declared api_filters for server-side filtering, plus `id`
      # (served locally by the find-by-id short-circuit). Run after
      # `define_schema`.
      def reconcile_filter_operators!
        filters = api_filters
        schema[:fields].each do |name, field|
          next unless field.type == 'Column'

          field.filter_operators = name == 'id' ? ID_OPS : Array(filters.dig(name, :ops))
        end
      end

      def fetch_records(filter)
        ids = extract_id_lookup(filter.condition_tree)
        return fetch_by_ids(ids) if ids

        fetch_page(filter.page, translate_filters(filter.condition_tree))
      end

      # Resolves a set of ids via the per-id `find_*` endpoint. Numeral has no
      # `id`/`ids` list filter, so there is no batch fetch — we de-duplicate and
      # fetch each distinct id once (one `GET /resource/:id` per id).
      def fetch_by_ids(ids)
        ids = Array(ids).reject { |id| id.to_s.empty? }.uniq
        return [] if ids.empty?

        ids.filter_map { |id| client_find(id) }
      end

      def fetch_page(page, params)
        return fetch_window(page, params) if page&.limit && page.limit > Client::MAX_PER_PAGE

        page_num, per_page = translate_page(page)
        client_list(**params, page: page_num, limit: per_page)
      end

      # Fetches a window larger than one API page by walking successive pages of
      # MAX_PER_PAGE and slicing to the requested [offset, offset + limit) range.
      def fetch_window(page, params)
        offset = page.offset.to_i
        limit  = page.limit.to_i
        start  = offset % Client::MAX_PER_PAGE
        page_num = (offset / Client::MAX_PER_PAGE) + 1
        collected = []
        loop do
          batch = client_list(**params, page: page_num, limit: Client::MAX_PER_PAGE)
          collected.concat(batch)
          break if batch.size < Client::MAX_PER_PAGE || collected.size >= start + limit

          page_num += 1
        end
        collected[start, limit] || []
      end

      def count_records(filter)
        ids = extract_id_lookup(filter.condition_tree)
        return fetch_by_ids(ids).size if ids

        client_count(**translate_filters(filter.condition_tree))
      end

      def client_list(**params)
        datasource.client.public_send("list_#{self.class.resource_plural}", **params)
      end

      def client_count(**params)
        datasource.client.public_send("count_#{self.class.resource_plural}", **params)
      end

      def client_find(id)
        datasource.client.public_send("find_#{self.class.resource_singular}", id)
      end

      def extract_id_lookup(node)
        return nil unless node.is_a?(Leaf) && node.field == 'id'

        case node.operator
        when Operators::EQUAL then [node.value]
        when Operators::IN    then Array(node.value)
        end
      end

      def translate_filters(condition_tree)
        Query::ConditionTreeTranslator.call(condition_tree, api_filters: api_filters)
      end

      def project(record, projection)
        return record if projection.nil?

        # Relation paths (containing ':') are populated by embed_relations, not
        # by the scalar projection. A projection of only relation paths yields
        # an empty scalar row — returning the full record here would leak every
        # column the caller did not ask for.
        wanted = Array(projection).map(&:to_s).reject { |p| p.include?(':') }
        wanted.to_h { |k| [k, record[k]] }
      end

      def translate_page(page)
        return [1, Client::MAX_PER_PAGE] if page.nil?

        per_page = page.limit&.positive? ? [page.limit, Client::MAX_PER_PAGE].min : Client::MAX_PER_PAGE
        page_num = (page.offset.to_i / per_page) + 1
        [page_num, per_page]
      end

      def ids_for(caller, filter)
        # An id-lookup filter already carries the ids — no need to round-trip to
        # the API just to read them back.
        ids = extract_id_lookup(filter.condition_tree)
        return ids.reject { |id| id.to_s.empty? }.uniq if ids

        list(caller, filter, ['id']).filter_map { |row| row['id'] }
      end

      def attrs_of(record)
        record.respond_to?(:attributes) ? record.attributes : record.to_h
      end

      # Returns the relation prefixes (everything before `:`) requested in the
      # projection - e.g. ["connected_account"] for ["id", "connected_account:name"].
      def relations_in(projection)
        Array(projection).map(&:to_s).filter_map { |p| p.split(':').first if p.include?(':') }.uniq
      end

      # Embeds the declared ManyToOne relations onto each row. The customizer's
      # relation decorator only handles emulated relations, so native datasource
      # relations like ours must populate the sub-record themselves.
      def embed_relations(rows, records, projection)
        return if projection.nil? || many_to_one_embeds.empty?

        sources = records.map { |r| attrs_of(r) }
        many_to_one_embeds.each do |embed|
          target = datasource.get_collection(embed[:collection])
          embed_many_to_one(
            rows, sources, projection,
            foreign_key: embed[:foreign_key], relation_name: embed[:relation_name],
            batch_fetcher: ->(ids) { target.send(:fetch_by_ids, ids) },
            serializer: ->(raw) { target.serialize(raw) }
          )
        end
      end

      # Bulk-fetches the related records for a ManyToOne relation in a single
      # batched call and writes the serialized record back onto each row.
      # rubocop:disable Metrics/ParameterLists
      def embed_many_to_one(rows, sources, projection, foreign_key:, relation_name:, batch_fetcher:, serializer:)
        return unless relations_in(projection).include?(relation_name)

        ids = sources.filter_map { |s| s[foreign_key] }.reject { |id| id.to_s.empty? }.uniq
        return if ids.empty?

        by_id = batch_fetcher.call(ids).to_h { |raw| [attrs_of(raw)['id'], raw] }
        rows.each_with_index do |row, i|
          fk_value = sources[i][foreign_key]
          next if fk_value.to_s.empty?

          raw = by_id[fk_value]
          row[relation_name] = raw && serializer.call(raw)
        end
      end
      # rubocop:enable Metrics/ParameterLists

      # Strips read-only columns and relation fields from a write payload,
      # deriving the deny-list from the schema's `is_read_only` flags so it can
      # never drift out of sync with the declared columns.
      def build_payload(data)
        drop = schema[:fields].reject { |_name, field| writable_column?(field) }.keys
        data.transform_keys(&:to_s).except(*drop)
      end

      def writable_column?(field)
        field.type == 'Column' && field.respond_to?(:is_read_only) && !field.is_read_only
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
