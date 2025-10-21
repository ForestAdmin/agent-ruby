module ForestAdminAgent
  module Utils
    module QueryValidator
      # Comprehensive list of forbidden SQL keywords and functions
      # These are blocked to prevent SQL injection attacks while still allowing SELECT queries
      FORBIDDEN_KEYWORDS = %w[
        DROP DELETE INSERT UPDATE ALTER
        CREATE TRUNCATE RENAME
        GRANT REVOKE
        EXECUTE EXEC
        UNION INTERSECT EXCEPT
        INTO OUTFILE DUMPFILE
        LOAD_FILE
        COPY
      ].freeze

      # Dangerous database functions that enable SQL injection attacks
      FORBIDDEN_FUNCTIONS = %w[
        pg_sleep pg_read_file pg_read_binary_file pg_ls_dir pg_read_binary_file
        SLEEP BENCHMARK WAITFOR
        LOAD_FILE
        UTL_FILE UTL_HTTP UTL_INADDR
        xp_cmdshell xp_regread xp_regwrite
      ].freeze

      # Enhanced SQL injection patterns
      INJECTION_PATTERNS = [
        /\bOR\s+\d+\s*=\s*\d+\b/i, # OR 1=1, OR 2=2, etc.
        /\bOR\s+TRUE\b/i,                     # OR TRUE
        /\bOR\s+FALSE\b/i,                    # OR FALSE
        /\bOR\s+['"].*['"]\s*=\s*['"].*['"]\b/i, # OR 'a'='a'
        /\bAND\s+\d+\s*=\s*\d+\b/i, # AND 1=1
        /;\s*DROP\b/i,                        # ; DROP
        /;\s*DELETE\b/i,                      # ; DELETE
        /;\s*INSERT\b/i,                      # ; INSERT
        /;\s*UPDATE\b/i,                      # ; UPDATE
        /--/,                                 # SQL comment
        %r{/\*},                               # Multi-line comment start
        %r{\*/}                                # Multi-line comment end
      ].freeze

      def self.valid?(query)
        query = query.strip
        raise ForestAdminDatasourceToolkit::Exceptions::ForestException, 'Query cannot be empty.' if query.empty?

        # Remove SQL comments first to prevent comment-based bypasses
        sanitized_query = remove_sql_comments(query)
        sanitized_query = remove_content_inside_strings(sanitized_query)

        check_select_only(sanitized_query)
        check_semicolon_placement(sanitized_query)
        check_forbidden_keywords(sanitized_query)
        check_forbidden_functions(sanitized_query)
        check_unbalanced_parentheses(sanitized_query)
        check_sql_injection_patterns(sanitized_query)

        true
      end

      class << self
        include ForestAdminDatasourceToolkit::Exceptions

        private

        def check_select_only(query)
          return if query.strip.upcase.start_with?('SELECT')

          raise ForestException, 'Only SELECT queries are allowed.'
        end

        def check_semicolon_placement(query)
          semicolon_count = query.scan(';').size

          raise ForestException, 'Only one query is allowed.' if semicolon_count > 1
          return if semicolon_count != 1 || query.strip[-1] == ';'

          raise ForestException, 'Semicolon must only appear as the last character in the query.'
        end

        def check_forbidden_keywords(query)
          FORBIDDEN_KEYWORDS.each do |keyword|
            if /\b#{Regexp.escape(keyword)}\b/i.match?(query)
              raise ForestException, "The query contains forbidden keyword: #{keyword}."
            end
          end
        end

        def check_forbidden_functions(query)
          FORBIDDEN_FUNCTIONS.each do |function|
            if /\b#{Regexp.escape(function)}\s*\(/i.match?(query)
              raise ForestException, "The query contains forbidden function: #{function}."
            end
          end
        end

        def check_unbalanced_parentheses(query)
          open_count = query.count('(')
          close_count = query.count(')')

          return if open_count == close_count

          raise ForestException, 'The query contains unbalanced parentheses.'
        end

        def check_sql_injection_patterns(query)
          INJECTION_PATTERNS.each do |pattern|
            raise ForestException, 'The query contains a potential SQL injection pattern.' if pattern.match?(query)
          end
        end

        def remove_sql_comments(query)
          # Remove single-line comments (--) but preserve them inside strings
          # Remove multi-line comments (/* */) but preserve them inside strings
          result = query.dup

          # First, temporarily replace string contents to protect them
          strings = []
          result = result.gsub(/'(?:[^']|\\')*'|"(?:[^"]|\\")*"/) do |match|
            strings << match
            "__STRING_#{strings.length - 1}__"
          end

          # Remove single-line comments
          result = result.gsub(/--[^\n]*/, '')

          # Remove multi-line comments
          result = result.gsub(%r{/\*.*?\*/}m, '')

          # Restore strings
          strings.each_with_index do |string, index|
            result = result.gsub("__STRING_#{index}__", string)
          end

          result
        end

        def remove_content_inside_strings(query)
          # remove content inside single and double quotes
          query.gsub(/'(?:[^']|\\')*'/, "''").gsub(/"(?:[^"]|\\")*"/, '""')
        end
      end
    end
  end
end
