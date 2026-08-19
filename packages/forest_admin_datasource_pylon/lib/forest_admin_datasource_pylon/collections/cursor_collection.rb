module ForestAdminDatasourcePylon
  module Collections
    # Base for the collections Pylon exposes through three endpoints: a plain
    # cursor-paginated listing (`GET /accounts`, `GET /contacts`: 60 requests per
    # minute), a search over the same pages (`POST /accounts/search`: 20) and a
    # single record (`GET /accounts/{id}`: 60).
    #
    # Their search endpoint filters `id` server-side, so — unlike Issue — they
    # declare it in `api_filters` and never need the primary-key short-circuit:
    # every predicate, `id` included and under an `or` as well, is translated and
    # answered by one search request. The routing below is therefore only about
    # spending the cheapest budget that answers the question exactly, never about
    # what Pylon can express.
    #
    # None of these endpoints takes a sort parameter, so `sortable_fields` stays
    # the empty default of the base and each collection names, through
    # `unsortable_warning`, the order it got instead of the one it asked for.
    class CursorCollection < BaseCollection
      include RecordSerialization
      include RelationEmbedder

      # Pylon documents no maximum number of values on an `in` filter; the chunk
      # keeps the request body and the page answering it bounded.
      ID_CHUNK_SIZE = 100

      def list(caller, filter, projection)
        records = fetch_records(caller, filter)
        rows = records.map { |record| project(record, projection) }
        embed_relations(records, rows, projection)
        rows
      end

      # The search endpoint filters `id` server-side, which is what lets a whole
      # page of foreign keys be read in one request per chunk.
      def records_indexed_by_id(ids)
        ids.each_slice(ID_CHUNK_SIZE).with_object({}) do |chunk, indexed|
          search_by_ids(chunk).each { |record| indexed[record['id']] = record }
        end
      end

      protected

      # Every collection read this way has a search endpoint, hence a table of
      # its own: the empty default of the base would silently turn each of its
      # filters into a refusal.
      def filter_table = raise(NotImplementedError, "#{self.class} did not implement filter_table")

      # One page of the listing endpoint, as a Client::SearchPage.
      def list_page(limit:, cursor:) = raise(NotImplementedError, "#{self.class} did not implement list_page")

      # One record straight from its own endpoint.
      def fetch_one(id) = raise(NotImplementedError, "#{self.class} did not implement fetch_one")

      private

      # The `id` filter goes through the translator rather than being written by
      # hand, so the shape on the wire is the one this collection's `api_filters`
      # produce — one spelling of an id filter, not two to keep in step. The
      # cursor is followed defensively: a chunk is asked for as a single page,
      # and Pylon is free to answer it over several.
      def search_by_ids(ids)
        pylon_filter = Query::ConditionTreeTranslator.call(Leaf.new('id', Operators::IN, ids),
                                                           api_filters: api_filters)
        records = walker.walk(offset: 0, limit: ids.size) do |batch, cursor|
          search_page(limit: batch, cursor: cursor, filter: pylon_filter, search_text: nil)
        end
        records.map { |record| serialize(record) }
      end

      def fetch_records(caller, filter)
        warn_unsortable(filter&.sort)

        with_resolved_relations(caller, filter) do |query|
          next listed_records(query) if browsing?(query)

          id = single_id_lookup(query)
          next page_window(records_by_id(id), query) if id

          search_records(caller, query)
        end
      end

      # Nothing to filter and nothing to search: the listing endpoint returns
      # the same records for a budget three times larger than the search one.
      def browsing?(filter)
        return true if filter.nil?

        filter.condition_tree.nil? && no_search?(filter)
      end

      # The walk of `search_records`, over the listing endpoint: it hands out
      # cursor pages just the same, it only takes no filter.
      def listed_records(filter)
        offset, limit = translate_page(filter&.page)

        records = walker.walk(offset: offset, limit: limit) { |batch, cursor| list_page(limit: batch, cursor: cursor) }
        records.map { |record| serialize(record) }
      end

      # A record detail is `id equals X` alone: reading it through the record
      # endpoint keeps the search budget for the pages that need it.
      #
      # Only a bare leaf takes that path. An `and` also carrying a scope is left
      # to the search endpoint, which filters the id and the rest server-side in
      # one request — where a lookup would have to apply the leftovers in memory,
      # and would refuse the ones it cannot evaluate there.
      def single_id_lookup(filter)
        tree = filter.condition_tree
        return nil unless tree.is_a?(Leaf) && no_search?(filter)

        ids = extract_id_lookup(tree)&.ids
        ids&.one? ? ids.first : nil
      end

      # A record the operator can no longer reach — deleted, or outside the
      # token's scope — reads as "no record" rather than as a failed page.
      def records_by_id(id)
        record = fetch_one(id)
        return [] if record.nil?

        serialized = serialize(record)
        matches_id?(serialized, id) ? [serialized] : []
      rescue APIError => e
        raise unless e.status == 404

        []
      end
    end
  end
end
