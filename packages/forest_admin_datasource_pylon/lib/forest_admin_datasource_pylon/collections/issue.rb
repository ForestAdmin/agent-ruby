module ForestAdminDatasourcePylon
  module Collections
    class Issue < BaseCollection
      include SchemaDefinition
      include RecordSerialization
      include Serializer
      include RelationEmbedder

      # `/issues/search` exposes no sort parameter, so the allow-list is empty and
      # every requested order is reported instead of being silently swallowed.
      # The mechanism stays in place for the collections whose endpoint sorts.
      PYLON_SORTABLE = {}.freeze

      # A primary-key lookup spends one `GET /issues/{id}` per id, against the
      # same 20 requests/minute budget the cursor walk is capped for, and the
      # retry policy only absorbs three 429s. The fan-out is therefore bounded
      # like the walk: truncated with a warning rather than turned into a rate
      # limit error halfway through the page. Story 9 (EXT-13) owns the
      # throttling that would let this cap grow.
      MAX_ID_LOOKUPS = 20

      def initialize(datasource, custom_fields: [])
        super(datasource, 'PylonIssue', custom_fields: custom_fields, searchable: true)
      end

      def list(caller, filter, projection)
        records = fetch_records(caller, filter)
        rows = records.map { |record| project(record, projection) }
        embed_relations(records, rows, projection)
        rows
      end

      protected

      def filter_table = ApiFilters

      def sortable_fields
        PYLON_SORTABLE
      end

      def unsortable_warning
        '[forest_admin_datasource_pylon] PylonIssue cannot honour the requested order; ' \
          'POST /issues/search always returns issues from the most recent to the oldest.'
      end

      def search_page(limit:, cursor:, filter:, search_text:)
        datasource.client.search_issues(limit: limit, cursor: cursor, filter: filter, search_text: search_text)
      end

      private

      def fetch_records(caller, filter)
        warn_unsortable(filter&.sort)

        with_resolved_relations(caller, filter) do |query|
          lookup = extract_id_lookup(query&.condition_tree)
          next search_records(caller, query) unless lookup

          ensure_searchless_lookup!(query)
          page_window(records_by_id(caller, lookup), query)
        end
      end

      # The records are already narrowed to the ids the filter asked for, so
      # applying the conditions left over by the short-circuit in memory cannot
      # return a record the API would have excluded. The reverse — dropping a
      # record over a condition memory evaluates differently from Pylon — is
      # ruled out by `extract_id_lookup`, which refuses such residuals.
      def records_by_id(caller, lookup)
        records = fetch_by_ids(lookup.ids)
        return records if lookup.residual.nil?

        lookup.residual.apply(records, self, timezone_for(caller))
      end

      # `GET /issues/{id}` accepts the issue number as well as the UUID, so a
      # record answering with an id other than the one asked for is dropped:
      # see `matches_id?`.
      def fetch_by_ids(ids)
        wanted = ids.first(MAX_ID_LOOKUPS)
        warn_truncated_lookup(ids.size) if ids.size > wanted.size

        wanted.filter_map do |id|
          record = fetch_issue(id)
          next if record.nil?

          serialized = serialize(record)
          serialized if matches_id?(serialized, id)
        end
      end

      # A record the operator can no longer reach — deleted, or outside the
      # token's scope — reads as "no record" rather than as a failed page.
      def fetch_issue(id)
        datasource.client.fetch_issue(id)
      rescue APIError => e
        raise unless e.status == 404

        nil
      end

      def warn_truncated_lookup(asked)
        ForestAdminDatasourcePylon.logger.warn(
          "[forest_admin_datasource_pylon] Asked for #{asked} issues by id, reading the first " \
          "#{MAX_ID_LOOKUPS}: one request per id would exhaust the rate limit of the agent. " \
          'Narrow the selection to reach the records past this point.'
        )
      end
    end
  end
end
