require 'active_support/time'

module ForestAdminAgent
  module Routes
    module Resources
      # Record-history route, mirroring the Node agent's `/_audit-trail/{collection}/:id`.
      #
      # Registered only when `config.audit_trail[:database]` is set, in which case the agent factory
      # built the store the capture layer writes to.
      class AuditTrail < AbstractAuthenticatedRoute
        include ForestAdminAgent::Utils
        include AuditTrailRoute

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
          add_route(
            'forest_audit_trail_state',
            'get',
            '/_audit-trail/:collection_name/:id/state',
            ->(args) { handle_state(args) }
          )

          self
        end

        def handle_request(args = {})
          context = build(args)
          context.permissions.can?(:read, context.collection)
          assert_record_in_scope(context, context.collection, args[:params]['id'])

          skip, limit = parse_pagination(args)
          filters = {
            collection: context.collection.name,
            # args[:params]['id'] is already Forest's packed id, the form the audit store keys on — plus any id
            # this record was filed under before a rename, each bounded by when it stopped being that id.
            record_id: record_segments(context.collection, args[:params]['id']),
            **parse_filters(args)
          }

          history = store.list_by_record(**filters, skip: skip, limit: limit, order: parse_sort(args))
          # `count` reflects the active filters (not the absolute total) and is independent of the page.
          count = store.count_by_record(**filters)

          {
            name: args[:params]['collection_name'],
            content: { data: history.map { |record| serialize_record(record) }, meta: meta(args, filters, count) }
          }
        end

        # Record as it stood at `timestamp`: the current record with every later entry undone. `data` is
        # null when the record did not exist yet (or not any more) at that instant. Shape matches the Node
        # agent's handleStateAt — `data` and nothing else.
        def handle_state(args = {})
          context = build(args)
          context.permissions.can?(:read, context.collection)
          # Authorizes and reads in one query: the record it hands back is the one the scope covered.
          current = scoped_record(
            context, context.collection, args[:params]['id'], audited_projection(context.collection)
          )

          timestamp = parse_state_timestamp(args)
          entries = store.list_since(
            collection: context.collection.name,
            record_id: record_segments(context.collection, args[:params]['id']),
            timestamp: timestamp
          )
          # Fully qualified: inside this class, `AuditTrail` is the route itself.
          state = ::ForestAdminAgent::AuditTrail::RecordState.at(current, entries)

          { name: args[:params]['collection_name'], content: { data: state } }
        end

        private

        # `availableUsers` rides along on the first fetch only — the front keeps the list it saw — and lists the
        # distinct authors of the entries the current filters match, whatever page was asked for. The identity
        # comes from the rows, so someone since renamed or removed still reads as they were when they acted.
        def meta(args, filters, count)
          return { count: count } unless first_fetch?(args)

          { count: count, availableUsers: available_users(filters) }
        end

        def first_fetch?(args)
          page = args.dig(:params, 'page')

          (page.is_a?(Hash) ? page['number'].to_i : 0) <= 1
        end

        def available_users(filters)
          store.authors_by_record(**filters).map do |author|
            { id: author[:user_id], firstName: author[:user_first_name],
              lastName: author[:user_last_name], email: author[:user_email] }
          end
        end

        # An ISO-8601 instant, or the same wall-clock forms the history filters accept, read in the request
        # timezone.
        def parse_state_timestamp(args)
          raw = args.dig(:params, 'timestamp').to_s
          raise Http::Exceptions::ValidationError, 'Missing timestamp' if raw.empty?
          # A wall-clock value carries no offset, so it belongs to the request timezone. Handing it to
          # Time.iso8601 would read it in the server's instead — silently, since it parses just fine.
          return parse_date_boundary(raw, request_timezone(args), :start) if wall_clock?(raw)

          begin
            Time.iso8601(raw).utc.iso8601(3)
          rescue ArgumentError
            parse_date_boundary(raw, request_timezone(args), :start)
          end
        end

        def wall_clock?(raw)
          DATE_ONLY.match?(raw) || DATE_TIME.match?(raw)
        end

        # JSON:API `sort`: `timestamp` → oldest first, anything else (absent/unsupported) → newest first.
        def parse_sort(args)
          args.dig(:params, 'sort').to_s == 'timestamp' ? 'asc' : 'desc'
        end

        # JSON:API pagination: 1-based page[number] (default 1) and page[size] (default 20, capped at
        # 100). Out-of-bound or non-numeric values fall back to the defaults rather than erroring.
        def parse_pagination(args)
          # `?page=foo` reaches us as a bare String, which `dig` refuses to walk into.
          page = args.dig(:params, 'page')
          page = {} unless page.is_a?(Hash)

          size = page['size'].to_i
          size = DEFAULT_PAGE_SIZE if size < 1
          size = MAX_PAGE_SIZE if size > MAX_PAGE_SIZE

          number = page['number'].to_i
          number = 1 if number < 1

          [(number - 1) * size, size]
        end

        def request_timezone(args)
          timezone = args.dig(:params, 'timezone').to_s

          timezone.empty? ? 'UTC' : timezone
        end

        def parse_filters(args)
          timezone = request_timezone(args)

          {
            user_ids: parse_user_ids(args.dig(:params, 'userIds')),
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
