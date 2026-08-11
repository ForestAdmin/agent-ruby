module ForestAdminDatasourcePylon
  module Collections
    class Issue < BaseCollection
      include SchemaDefinition
      include Serializer

      # `/issues/search` exposes no sort parameter, so the allow-list is empty and
      # every requested order is reported instead of being silently swallowed.
      # The mechanism stays in place for the collections whose endpoint sorts.
      PYLON_SORTABLE = {}.freeze

      def initialize(datasource, custom_fields: [])
        super(datasource, 'PylonIssue', custom_fields: custom_fields, searchable: true)
      end

      def list(caller, filter, projection)
        fetch_records(caller, filter).map { |record| project(record, projection) }
      end

      protected

      # A custom field is filtered through its Pylon slug, with the operators the
      # integrator declared on the column.
      def api_filters
        @api_filters ||= custom_fields.each_with_object(ApiFilters::API_FILTERS.dup) do |cf, filters|
          filters[cf[:column_name]] = ApiFilters.for_custom_field(cf[:schema])
        end
      end

      # Declarations outside this list are dropped at registration, so the
      # schema never advertises an operator the translator would refuse.
      def allowed_custom_field_operators
        ApiFilters::CUSTOM_FIELD_OPS.keys
      end

      private

      def fetch_records(caller, filter)
        lookup = extract_id_lookup(filter&.condition_tree)
        return page_window(records_by_id(caller, lookup), filter) if lookup

        search_records(caller, filter)
      end

      def search_records(caller, filter)
        warn_unsortable(filter&.sort)
        pylon_filter  = build_pylon_filter(caller, filter)
        search_text   = filter&.search
        offset, limit = translate_page(filter&.page)

        issues = walker.walk(offset: offset, limit: limit) do |batch, cursor|
          datasource.client.search_issues(limit: batch, cursor: cursor,
                                          filter: pylon_filter, search_text: search_text)
        end
        issues.map { |issue| serialize(issue) }
      end

      # The records are already narrowed to the ids the filter asked for, so
      # applying the conditions left over by the short-circuit in memory cannot
      # return a record the API would have excluded. The reverse — dropping a
      # record over a condition memory evaluates differently from Pylon — is
      # ruled out by `extract_id_lookup`, which refuses such residuals.
      def records_by_id(caller, lookup)
        records = fetch_by_ids(lookup.ids).map { |issue| serialize(issue) }
        return records if lookup.residual.nil?

        lookup.residual.apply(records, self, timezone_for(caller))
      end

      # Sliced after the lookup, not before, so ids that resolved to nothing
      # (404) do not eat into the requested window.
      def page_window(records, filter)
        offset, limit = translate_page(filter&.page)
        records[offset, limit] || []
      end

      # A record the operator can no longer reach — deleted, or outside the
      # token's scope — reads as "no record" rather than as a failed page.
      def fetch_by_ids(ids)
        ids.filter_map do |id|
          datasource.client.fetch_issue(id)
        rescue APIError => e
          raise unless e.status == 404

          nil
        end
      end

      def warn_unsortable(sort)
        return if sort.nil? || sort.empty? || default_pk_sort?(sort)
        return if translate_sort(sort, PYLON_SORTABLE).first

        ForestAdminDatasourcePylon.logger.warn(
          '[forest_admin_datasource_pylon] PylonIssue cannot honour the requested order; ' \
          'POST /issues/search always returns issues from the most recent to the oldest.'
        )
      end

      def walker
        @walker ||= Pagination::CursorWalker.new
      end
    end
  end
end
