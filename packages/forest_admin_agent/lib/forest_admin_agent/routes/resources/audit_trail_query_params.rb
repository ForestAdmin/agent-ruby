module ForestAdminAgent
  module Routes
    module Resources
      # The query params every audit-trail listing reads the same way, the per-record history and the
      # cross-collection timeline alike, so a filter cannot mean one thing on one route and another on the
      # other. Mirrors the Node agent's `audit-trail/query-params.ts`.
      module AuditTrailQueryParams
        DEFAULT_PAGE_SIZE = 20
        MAX_PAGE_SIZE = 100
        DATE_ONLY = /\A\d{4}-\d{2}-\d{2}\z/
        # Wall-clock datetime, `T` or space separator, seconds optional: `YYYY-MM-DD[T ]HH:mm[:ss]`.
        DATE_TIME = /\A(\d{4}-\d{2}-\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?\z/
        OPERATIONS = %w[create update delete action action_failed].freeze

        private

        # `?page=foo` reaches us as a bare String, which `dig` refuses to walk into.
        def page_param(args)
          page = args.dig(:params, 'page')

          page.is_a?(Hash) ? page : {}
        end

        # page[size] defaults to 20 and is capped at 100.
        def parse_page_size(args)
          size = page_param(args)['size'].to_i

          size < 1 ? DEFAULT_PAGE_SIZE : [size, MAX_PAGE_SIZE].min
        end

        def request_timezone(args)
          timezone = args.dig(:params, 'timezone').to_s

          timezone.empty? ? 'UTC' : timezone
        end

        def parse_filters(args)
          timezone = request_timezone(args)

          {
            user_ids: parse_user_ids(args.dig(:params, 'userIds')),
            operations: parse_operations(args.dig(:params, 'operations')),
            fields: parse_fields(args.dig(:params, 'fields')),
            search: parse_search(args.dig(:params, 'search')),
            start_timestamp: parse_date_boundary(args.dig(:params, 'startDate'), timezone, :start),
            end_timestamp: parse_date_boundary(args.dig(:params, 'endDate'), timezone, :end)
          }.compact
        end

        # Free text, trimmed; blank means no filter rather than a term that matches everything.
        def parse_search(raw)
          term = raw.to_s.strip

          term.empty? ? nil : term
        end

        # Comma-separated field names, kept verbatim (a name may hold a dot). Empty after parsing → no filter.
        def parse_fields(raw)
          return nil if raw.nil?

          names = (raw.is_a?(Array) ? raw : raw.to_s.split(',')).map { |name| name.to_s.strip }.reject(&:empty?)
          names.empty? ? nil : names
        end

        # Comma-separated, from a closed set. An unrecognized value is rejected rather than dropped: a silently
        # ignored filter returns unfiltered rows into a list the caller believes is filtered.
        def parse_operations(raw)
          tokens = raw.to_s.split(',').map(&:strip).reject(&:empty?)
          unknown = tokens.find { |token| !OPERATIONS.include?(token) }

          if unknown
            raise Http::Exceptions::ValidationError,
                  "Invalid operation: \"#{unknown}\" (expected one of #{OPERATIONS.join(", ")})"
          end

          tokens.empty? ? nil : tokens
        end

        # Comma-separated integer ids; non-numeric tokens are dropped. Empty after parsing → no filter.
        def parse_user_ids(raw)
          return nil if raw.nil? || raw.to_s.empty?

          ids = raw.to_s.split(',').map(&:strip).grep(/\A\d+\z/).map(&:to_i)
          ids.empty? ? nil : ids
        end

        # `startDate`/`endDate` accept a bare day (`YYYY-MM-DD`) or a wall-clock datetime
        # (`YYYY-MM-DD[T ]HH:mm[:ss]`), read as local time in the request timezone and returned as a UTC
        # ISO instant the store can compare against stored timestamps.
        def parse_date_boundary(raw, timezone, boundary)
          return nil if raw.nil? || raw.to_s.empty?

          zone = Time.find_zone(timezone)
          raise Http::Exceptions::ValidationError, "Invalid timezone: \"#{timezone}\"" if zone.nil?

          instant = begin
            local_instant(zone, raw.to_s, boundary)
          rescue ArgumentError
            nil
          end

          if instant.nil?
            raise Http::Exceptions::ValidationError,
                  "Invalid date: \"#{raw}\" (expected YYYY-MM-DD or YYYY-MM-DDTHH:mm)"
          end

          instant.utc.iso8601(3)
        end

        def local_instant(zone, raw, boundary)
          if DATE_ONLY.match?(raw)
            day = zone.parse(raw)
            # Bare day → start (00:00:00.000) or end (23:59:59.999) of that local day.
            boundary == :end ? day.end_of_day : day.beginning_of_day
          elsif (match = DATE_TIME.match(raw))
            date, hours, minutes, seconds = match.captures
            base = zone.parse("#{date}T#{hours}:#{minutes}")
            if seconds
              base.change(sec: seconds.to_i, usec: 0)
            elsif boundary == :end
              # Minutes-only end boundary stays inclusive to :59.999; start stays at :00.000.
              base.change(sec: 59, usec: 999_000)
            else
              base
            end
          end
        end
      end
    end
  end
end
