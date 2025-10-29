module ForestAdminAgent
  module Utils
    module QueryValidator
      FORBIDDEN_KEYWORDS = %w[DROP DELETE INSERT UPDATE ALTER].freeze
      INJECTION_PATTERNS = [
        /\bOR\s+1=1\b/i # OR 1=1
      ].freeze

      def self.valid?(query)
        query = query.strip
        raise Http::Exceptions::BadRequestError, 'Query cannot be empty.' if query.empty?

        sanitized_query = remove_content_inside_strings(query)
        check_select_only(sanitized_query)
        check_semicolon_placement(sanitized_query)
        check_forbidden_keywords(sanitized_query)
        check_unbalanced_parentheses(sanitized_query)
        check_sql_injection_patterns(sanitized_query)

        true
      end

      class << self
        private

        def check_select_only(query)
          return if query.strip.upcase.start_with?('SELECT')

          raise Http::Exceptions::BadRequestError, 'Only SELECT queries are allowed.'
        end

        def check_semicolon_placement(query)
          semicolon_count = query.scan(';').size

          raise Http::Exceptions::BadRequestError, 'Only one query is allowed.' if semicolon_count > 1
          return if semicolon_count != 1 || query.strip[-1] == ';'

          raise Http::Exceptions::BadRequestError, 'Semicolon must only appear as the last character in the query.'
        end

        def check_forbidden_keywords(query)
          FORBIDDEN_KEYWORDS.each do |keyword|
            next unless /\b#{Regexp.escape(keyword)}\b/i.match?(query)

            raise Http::Exceptions::BadRequestError.new(
              "The query contains forbidden keyword: #{keyword}.",
              details: { forbidden_keyword: keyword }
            )
          end
        end

        def check_unbalanced_parentheses(query)
          open_count = query.count('(')
          close_count = query.count(')')

          return if open_count == close_count

          raise Http::Exceptions::BadRequestError.new(
            'The query contains unbalanced parentheses.',
            details: { open_count: open_count, close_count: close_count }
          )
        end

        def check_sql_injection_patterns(query)
          INJECTION_PATTERNS.each do |pattern|
            next unless pattern.match?(query)

            raise Http::Exceptions::BadRequestError, 'The query contains a potential SQL injection pattern.'
          end
        end

        def remove_content_inside_strings(query)
          # remove content inside single and double quotes
          query.gsub(/'(?:[^']|\\')*'/, '').gsub(/"(?:[^"]|\\")*"/, '')
        end
      end
    end
  end
end
