module ForestAdminDatasourceZendesk
  module Collections
    # Including classes must define `zendesk_resource`, `find_one(id)`,
    # `sortable_fields`, and `serialize(record)`.
    module Searchable
      def list(caller, filter, projection)
        records = ids_in_filter(filter) ? find_records_by_id(filter) : search_records(caller, filter)
        records.map { |r| project(serialize(r), projection) }
      end

      protected

      def aggregate_count(caller, filter)
        datasource.client.count(zendesk_resource, query: build_zendesk_query(caller, filter))
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
                                 query: build_zendesk_query(caller, filter),
                                 sort_by: sort_by, sort_order: sort_order,
                                 page: page, per_page: per_page)
      end
    end
  end
end
