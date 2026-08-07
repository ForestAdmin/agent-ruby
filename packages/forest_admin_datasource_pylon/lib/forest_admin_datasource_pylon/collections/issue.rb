module ForestAdminDatasourcePylon
  module Collections
    class Issue < BaseCollection
      include SchemaDefinition
      include Serializer

      def initialize(datasource, custom_fields: [])
        super(datasource, 'PylonIssue', custom_fields: custom_fields)
      end

      def list(_caller, filter, projection)
        fetch_records(filter).map { |issue| project(serialize(issue), projection) }
      end

      private

      def fetch_records(filter)
        ids = extract_id_lookup(filter&.condition_tree)
        return fetch_by_ids(ids) if ids

        warn_ignored_filter(filter)
        offset, limit = translate_page(filter&.page)
        walker.walk(offset: offset, limit: limit) do |batch, cursor|
          datasource.client.search_issues(limit: batch, cursor: cursor)
        end
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

      # Condition-tree translation and free-text search land in a later story.
      # Until then a filter the collection cannot honour is dropped, which would
      # otherwise silently return unfiltered rows.
      def warn_ignored_filter(filter)
        ignored = []
        ignored << 'condition tree' unless filter&.condition_tree.nil?
        ignored << 'search' unless filter&.search.nil? || filter.search.to_s.empty?
        return if ignored.empty?

        ForestAdminDatasourcePylon.logger.warn(
          "[forest_admin_datasource_pylon] PylonIssue ignored the #{ignored.join(" and ")} of this query; " \
          'filtering is not implemented yet, so the returned records are unfiltered.'
        )
      end

      def walker
        @walker ||= Pagination::CursorWalker.new
      end
    end
  end
end
