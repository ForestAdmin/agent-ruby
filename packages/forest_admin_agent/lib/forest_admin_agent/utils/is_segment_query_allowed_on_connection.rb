module ForestAdminAgent
  module Utils
    module IsSegmentQueryAllowedOnConnection
      # Check if a segment query is allowed on a specific connection
      # This handles both single queries and UNION queries for multi-segment operations
      #
      # @param collection_permissions [Hash] The collection permissions containing liveQuerySegments
      # @param segment_query [String] The SQL query to validate
      # @param connection_name [String] The database connection name
      # @return [Boolean] true if the query is allowed, false otherwise
      def self.allowed?(collection_permissions, segment_query, connection_name)
        return false if collection_permissions.nil? ||
                        collection_permissions[:liveQuerySegments].nil? ||
                        connection_name.nil? ||
                        connection_name.empty?

        # Get all queries for the specified connection
        queries = collection_permissions[:liveQuerySegments]
                  .select { |segment| segment[:connectionName] == connection_name }
                  .map { |segment| segment[:query] }

        # Handle UNION queries made by the FRONT to display available actions on details view
        # This is used on related data (Has Many relationships) to detect available
        # Smart Actions restricted to segment when a Smart Action is available on multiple SQL segments
        union_queries = segment_query.split('/*MULTI-SEGMENTS-QUERIES-UNION*/ UNION ')

        if union_queries.length > 1
          # For UNION queries, all sub-queries must be authorized
          authorized_queries = queries.to_set { |query| query.gsub(/;\s*\z/i, '').strip }

          return union_queries.all? { |union_query| authorized_queries.include?(union_query.strip) }
        end

        # For single queries, check if it matches exactly
        queries.any?(segment_query)
      end
    end
  end
end
