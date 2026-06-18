require 'active_support/time'

module ForestAdminAgent
  module Routes
    module Resources
      # Record-history route, mirroring the Node agent's `/_audit-trail/{collection}/:id`.
      #
      # Registered only when an `audit_trail` option carrying a readable store was provided to the
      # agent. The store is expected to respond to `list_by_record` and `count_by_record`.
      class AuditTrail < AbstractAuthenticatedRoute
        include ForestAdminAgent::Utils

        DEFAULT_PAGE_SIZE = 20
        MAX_PAGE_SIZE = 100
        DATE_ONLY = /\A\d{4}-\d{2}-\d{2}\z/
        # Wall-clock datetime, `T` or space separator, seconds optional: `YYYY-MM-DD[T ]HH:mm[:ss]`.
        DATE_TIME = /\A(\d{4}-\d{2}-\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?\z/

        def setup_routes
          return self unless store

          add_route(
            'forest_audit_trail',
            'get',
            '/_audit-trail/:collection_name/:id',
            ->(args) { handle_request(args) }
          )

          self
        end

        def handle_request(args = {})
          context = build(args)
          context.permissions.can?(:read, context.collection)

          skip, limit = parse_pagination(args)
          filters = {
            collection: context.collection.name,
            # args[:params]['id'] is already Forest's packed id, the form the audit store keys on.
            record_id: args[:params]['id'],
            **parse_filters(args)
          }

          history = store.list_by_record(**filters, skip: skip, limit: limit, order: parse_sort(args))
          # `count` reflects the active filters (not the absolute total) and is independent of the page.
          count = store.count_by_record(**filters)

          {
            name: args[:params]['collection_name'],
            content: { data: history.map { |record| serialize(record) }, meta: { count: count } }
          }
        end

        private

        # Camelize only the top-level keys; previous/new value hashes keep the record's own column names.
        def serialize(record)
          record.to_h.transform_keys { |key| key.to_s.camelize(:lower) }
        end

        # JSON:API `sort`: `timestamp` → oldest first, anything else (absent/unsupported) → newest first.
        def parse_sort(args)
          args.dig(:params, 'sort').to_s == 'timestamp' ? 'asc' : 'desc'
        end

        # JSON:API pagination: 1-based page[number] (default 1) and page[size] (default 20, capped at
        # 100). Out-of-bound or non-numeric values fall back to the defaults rather than erroring.
        def parse_pagination(args)
          size = args.dig(:params, 'page', 'size').to_i
          size = DEFAULT_PAGE_SIZE if size < 1
          size = MAX_PAGE_SIZE if size > MAX_PAGE_SIZE

          number = args.dig(:params, 'page', 'number').to_i
          number = 1 if number < 1

          [(number - 1) * size, size]
        end

        def parse_filters(args)
          timezone = args.dig(:params, 'timezone').to_s
          timezone = 'UTC' if timezone.empty?

          {
            user_ids: parse_user_ids(args.dig(:params, 'userIds')),
            start_timestamp: parse_date_boundary(args.dig(:params, 'startDate'), timezone, :start),
            end_timestamp: parse_date_boundary(args.dig(:params, 'endDate'), timezone, :end)
          }.compact
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

        def store
          config = ForestAdminAgent::Facades::Container.config_from_cache
          config && config[:audit_trail] && config[:audit_trail][:store]
        end
      end
    end
  end
end
