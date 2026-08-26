module ForestAdminDatasourcePylon
  module Collections
    class Issue < BaseCollection
      include SchemaDefinition
      include RecordSerialization
      include Serializer
      include RelationEmbedder
      include MessagesEmbedder
      include IdLookupReader

      # `/issues/search` exposes no sort parameter, so the allow-list is empty and
      # every requested order is reported instead of being silently swallowed.
      # The mechanism stays in place for the collections whose endpoint sorts.
      PYLON_SORTABLE = {}.freeze

      # A primary-key lookup spends one `GET /issues/{id}` per id, sequentially.
      # The fan-out is bounded like the cursor walk, and for the same reason:
      # `RateLimiter` keeps the requests inside the 300 a minute that endpoint
      # grants, but nothing makes two hundred round-trips fast.
      #
      # What it bounds is one page, not the selection behind it: the window is
      # taken off the ids first, so a selection wider than this is read a page
      # at a time rather than truncated at its first #{MAX_ID_LOOKUPS}. See
      # `IdLookupReader`, and the one case that cannot be paged.
      MAX_ID_LOOKUPS = 20

      # The shape of one message inside the `messages` column. Field names follow
      # the columns of this collection rather than the payload: Pylon spells them
      # `message_html` and `timestamp`, which would put two conventions in the
      # same schema for the operator to reconcile.
      MESSAGE_THREAD_SCHEMA = {
        'id' => 'String',
        'body_html' => 'String',
        'is_private' => 'Boolean',
        'source' => 'String',
        'thread_id' => 'String',
        'file_urls' => 'Json',
        'created_at' => 'Date',
        'author_name' => 'String',
        'author_email' => 'String',
        'author_avatar_url' => 'String',
        'author_contact_id' => 'String',
        'author_user_id' => 'String'
      }.freeze

      # One thread is one `GET /issues/{id}/messages`, and a thread is the whole
      # conversation rather than a page of it. A list view asking for more of
      # them than this reads the first ones and reports the rest, for the same
      # reason MAX_ID_LOOKUPS bounds the primary-key fan-out — sequential
      # round-trips, each carrying an unbounded payload. Lower than
      # MAX_ID_LOOKUPS because of that payload, not because of the quota: the
      # endpoint grants 120 requests a minute.
      MAX_MESSAGE_EMBEDS = 10

      # `body_html` is the first message of the thread, which `POST /issues`
      # requires and `PATCH /issues/{id}` does not carry; `author_unverified`
      # qualifies that message and travels with it.
      CREATE_ONLY = %w[body_html author_unverified].freeze

      # Pylon creates every issue as `new`, of the type it decides, and takes
      # both on an update only.
      UPDATE_ONLY = %w[state type].freeze

      def initialize(datasource, custom_fields: [])
        super(datasource, 'PylonIssue', custom_fields: custom_fields, searchable: true)
      end

      def list(caller, filter, projection)
        records = fetch_records(caller, filter)
        rows = records.map { |record| project(record, projection) }
        embed_relations(records, rows, projection)
        embed_messages(records, rows) if want_messages?(projection)
        rows
      end

      protected

      def filter_table = ApiFilters

      def create_record(payload) = datasource.client.create_issue(payload)
      def update_record(id, payload) = datasource.client.update_issue(id, payload)
      def delete_record(id) = datasource.client.delete_issue(id)

      def create_only_fields = CREATE_ONLY
      def update_only_fields = UPDATE_ONLY

      # An issue is read through `GET /issues/{id}`, one request per record: a
      # selection resolved or compared that way spends the write budget twice
      # over, so it divides the records one pass reaches rather than fitting
      # beside them.
      def requests_per_record_read = 1

      # Never past the primary-key fan-out either: a write resolving named ids
      # through `list` reads them one request apiece, and a resolution the page
      # cap trimmed would write to a subset of the selection while reporting the
      # whole of it. The budget is the tighter of the two at today's numbers;
      # the clamp keeps that true if either moves.
      def max_resolvable_ids(reads: 0) = [super, MAX_ID_LOOKUPS].min

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
          records_by_id(caller, lookup, query)
        end
      end
    end
  end
end
