module ForestAdminDatasourceZendesk
  module Collections
    # Shared list/aggregate/find boilerplate for collections backed by the
    # Zendesk Search API (currently User and Organization). Tickets have a
    # custom list pipeline (relation embedding, requester_email enrichment),
    # so they do *not* include this — the contract is documented in
    # BaseCollection.
    #
    # Including classes must define:
    #   - `zendesk_resource` returning the Search API type (`'user'`, `'organization'`)
    #   - `find_one(id)` returning a single record from the Zendesk client
    #   - `sortable_fields` returning the {forest_field => zendesk_sort_by} map
    #   - `serialize(record)` mapping Zendesk attributes to a Forest hash
    module Searchable
      def list(caller, filter, projection)
        records = ids_in_filter(filter) ? find_records_by_id(filter) : search_records(caller, filter)
        records.map { |r| project(serialize(r), projection) }
      end

      protected

      def aggregate_count(caller, filter)
        datasource.client.count(zendesk_resource, query: compose_full_query(caller, filter))
      end

      private

      def ids_in_filter(filter)
        extract_id_lookup(filter.condition_tree)
      end

      def find_records_by_id(filter)
        ids_in_filter(filter).filter_map { |id| find_one(id) }
      end

      def search_records(caller, filter)
        sort_by, sort_order = translate_sort(filter.sort, sortable_fields)
        page, per_page      = translate_page(filter.page)

        datasource.client.search(zendesk_resource,
                                 query: compose_full_query(caller, filter),
                                 sort_by: sort_by, sort_order: sort_order,
                                 page: page, per_page: per_page)
      end

      # Both list and count must build the query the same way: condition tree
      # AND `filter.search`. A previous version of search_records omitted the
      # search term, which made the count badge disagree with the rendered
      # list ("100 results, count says 5") — guard against that by sharing
      # this builder.
      def compose_full_query(caller, filter)
        translated = ForestAdminDatasourceZendesk::Query::ConditionTreeTranslator.call(
          filter.condition_tree, timezone: timezone_for(caller),
                                 custom_fields: datasource.custom_field_mapping
        )
        [translated, filter.search].compact.reject(&:empty?).join(' ')
      end
    end
  end
end
