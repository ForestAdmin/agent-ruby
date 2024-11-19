module ForestAdminAgent
  module Utils
    class QueryValidator
      include ForestAdminDatasourceToolkit::Exceptions

      def initialize(query)
        @query = query.strip
      end

      def valid?
        raise ForestException, 'Query cannot be empty' if @query.empty?
        raise ForestException, 'Only SELECT queries are allowed' unless select_query?
        raise ForestException, 'Only one query is allowed' if multiple_requests?
        raise ForestException, 'Forbidden SQL keywords detected' if forbidden_keywords?
        raise ForestException, 'Unbalanced parentheses in query' if unbalanced_parentheses?

        true
      end

      private

      def select_query?
        @query.strip.upcase.start_with?('SELECT')
      end

      def multiple_requests?
        # check ";" dans le where ?
        # faire check si ";" en dernier caractère
        @query.split(';').size > 1
      end

      def forbidden_keywords?
        forbidden_keywords = %w[DROP DELETE UPDATE INSERT]
        forbidden_keywords.any? { |word| @query.upcase.include?(word) }
      end

      def unbalanced_parentheses?
        # ignorer parentheses dans les where
        @query.count('(') != @query.count(')')
      end
    end
  end
end
