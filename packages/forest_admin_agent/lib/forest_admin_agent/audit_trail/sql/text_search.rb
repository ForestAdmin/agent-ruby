require 'json'

module ForestAdminAgent
  module AuditTrail
    module Sql
      # SQL keeping only the audit entries a free-text term matches, case-insensitively and as a substring:
      # the action's name, who acted, and the keys and values recorded on both sides of the change — at any
      # depth, since only the changed leaves of a JSON column are stored and the term has to reach them.
      #
      # Deliberately not searched: operation, correlation_key, record_id, collection, status and timestamp.
      # Machine identifiers nobody searches for, and matching them turns one term into a pile of confusing
      # hits.
      #
      # The values are matched against the JSON document as text, which is what lets one condition reach any
      # depth and compose with pagination and the count. It cannot use an index, which is affordable here
      # because a history query is already narrowed to one record.
      class TextSearch
        TEXT_COLUMNS = %w[action_name user_first_name user_last_name user_email].freeze
        JSON_COLUMNS = %w[previous_values new_values].freeze
        # `!` rather than a backslash: MySQL treats a backslash as an escape inside string literals too, so
        # `ESCAPE '\'` needs doubling there and nowhere else.
        ESCAPE = '!'.freeze
        # A masked value is stored as this. It is removed before matching, so a search for "redacted" cannot
        # hit it — and since the real value was never recorded, searching that finds nothing either. A search
        # must never confirm a value the trail refused to keep.
        REDACTED = Recording::REDACTED

        def initialize(connection)
          @connection = connection
        end

        def condition(term)
          text = term.to_s.downcase
          # The value objects are matched as serialized JSON, where a quote, a backslash or a newline is
          # escaped — so `15" monitor` sits in the document as `15\" monitor` and the raw term would never
          # find it. Escaping the term the same way makes it match, and stops a bare quote from matching the
          # document's own structure.
          clauses = TEXT_COLUMNS.map { |column| like(column, text) }
          clauses += JSON_COLUMNS.map { |column| like(searchable_json(column), json_escaped(text)) }

          clauses.join(' OR ')
        end

        private

        def like(expression, text)
          "LOWER(#{expression}) LIKE #{@connection.quote("%#{escape(text)}%")} ESCAPE '#{ESCAPE}'"
        end

        # What JSON generation would have done to the term: `to_json` on the string, minus its own quotes.
        def json_escaped(text)
          text.to_json[1..-2]
        end

        def searchable_json(column)
          "REPLACE(#{as_text(column)}, #{@connection.quote(REDACTED)}, '')"
        end

        def as_text(column)
          adapter = @connection.adapter_name.downcase

          case adapter
          when /postgres/ then "#{column}::text"
          when /sqlite/ then column
          when /mysql|maria/ then "CAST(#{column} AS CHAR)"
          else
            raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                  "Searching the audit trail is not supported on #{adapter}"
          end
        end

        def escape(term)
          term.gsub(/[!%_]/) { |char| "#{ESCAPE}#{char}" }
        end
      end
    end
  end
end
