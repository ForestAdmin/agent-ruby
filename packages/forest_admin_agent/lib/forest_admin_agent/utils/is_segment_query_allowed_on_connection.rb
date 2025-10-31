module ForestAdminAgent
  module Utils
    module IsSegmentQueryAllowedOnConnection
      # Check if a segment query is allowed on a specific connection
      # This handles both single queries and UNION queries for multi-segment operations
      def self.allowed?(collection_permissions, segment_query, connection_name)
        return false if connection_name.nil? || connection_name.empty?

        # Get all queries for the specified connection
        queries = collection_permissions[:liveQuerySegments]
                  .select { |segment| segment[:connectionName] == connection_name }
                  .map { |segment| segment[:query] }

        # Handle UNION queries made by the FRONT to display available actions
        # Smart Actions restricted to segment when a Smart Action is available on multiple SQL segments
        union_queries = segment_query.split('/*MULTI-SEGMENTS-QUERIES-UNION*/ UNION ')

        if union_queries.length > 1
          authorized_queries = queries.to_set { |query| query.gsub(/;\s*\z/i, '').strip }

          return union_queries.all? { |union_query| authorized_queries.include?(union_query.strip) }
        end

        queries.any?(segment_query)
      end
    end
  end
end
