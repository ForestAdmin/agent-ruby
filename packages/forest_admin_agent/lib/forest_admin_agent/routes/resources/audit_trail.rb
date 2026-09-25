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
          # Before the audit database is touched, for the 404 it raises — and for what it saw of the record
          # while the rows below were still being chosen, which the read after them can no longer see.
          gone_at_check = assert_record_in_scope(context, context.collection, args[:params]['id'])

          filters = {
            collection: context.collection.name,
            # args[:params]['id'] is already Forest's packed id, the form the audit store keys on — plus any id
            # this record was filed under before a rename, each bounded by when it stopped being that id.
            record_id: record_segments(context.collection, args[:params]['id']),
            **parse_filters(args)
          }

          data, count, authors = if gone_at_check && filters.slice(:search, :fields).any?
                                   history_matched_after_withholding(context, args, filters, gone_at_check)
                                 else
                                   history_matched_in_store(context, args, filters, gone_at_check)
                                 end

          {
            name: args[:params]['collection_name'],
            content: { data: data.map { |record| serialize_record(record) }, meta: meta(args, count, authors) }
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
          # Nothing left to evaluate a scope against, so the reconstruction is tested in its own right below
          # — whatever the read after the rows finds under this id by then.
          gone_at_check = current.nil? ? context.permissions.get_scope(context.collection) : nil

          timestamp = parse_state_timestamp(args)
          entries = store.list_since(
            collection: context.collection.name,
            record_id: record_segments(context.collection, args[:params]['id']),
            timestamp: timestamp
          )
          # Fully qualified: inside this class, `AuditTrail` is the route itself.
          state = ::ForestAdminAgent::AuditTrail::RecordState.at(current, entries)
          # Asked again now, for the same reason the history route asks, and the same way: the record read
          # above can be deleted — or an id that was gone then be taken by somebody else's record — while the
          # audit read is in flight.
          withholding_scope = withholding_scope_for(context, context.collection, args[:params]['id'],
                                                    gone_at_check)

          { name: args[:params]['collection_name'],
            content: { data: answerable_state(state, withholding_scope, context, args[:params]['id']) } }
        end

        private

        # The history route withholds a gone record's captured values from a caller whose scope they fail, and
        # this route is nothing but those values reassembled: without the same test they come back one request
        # away. A reconstruction the scope cannot answer withholds too — absent is not the same as passing.
        def answerable_state(state, scope, context, packed_id)
          return state if state.nil? || scope.nil?

          withholding = Withholding.new(context.collection, scope, context.caller.timezone)
          # The reconstruction can sit on the far side of a primary-key move this route cannot see, so the
          # requested id does not answer for a key the trail redacted — only for one never captured at all.
          in_scope?(state, packed_id, withholding, id_answers_for_keys: false) ? state : nil
        end

        # `availableUsers` rides along on the first fetch only — the front keeps the list it saw — and lists the
        # distinct authors of the entries the current filters match, whatever page was asked for. The identity
        # comes from the rows, so someone since renamed or removed still reads as they were when they acted.
        def meta(args, count, authors)
          return { count: count } unless first_fetch?(args)

          { count: count, availableUsers: authors.call.map { |author| available_user(author) } }
        end

        def first_fetch?(args)
          page = args.dig(:params, 'page')

          (page.is_a?(Hash) ? page['number'].to_i : 0) <= 1
        end

        def available_user(author)
          { id: author[:user_id], firstName: author[:user_first_name],
            lastName: author[:user_last_name], email: author[:user_email] }
        end

        def history_matched_in_store(context, args, filters, gone_at_check)
          skip, limit = parse_pagination(args)
          history = store.list_by_record(**filters, skip: skip, limit: limit, order: parse_sort(args))
          # `count` reflects the active filters (not the absolute total) and is independent of the page.
          count = store.count_by_record(**filters)

          [withheld(context, args, history, gone_at_check), count, -> { store.authors_by_record(**filters) }]
        end

        # Matched in SQL, `search` and `fields` would test the values as captured, so which rows come back, the
        # count and the authors would still say what the withholding hides — one probe per character. They are
        # matched against what is served instead, which means paging the whole history here. Only for a record
        # gone at the check: one in scope then was the caller's to read whole.
        def history_matched_after_withholding(context, args, filters, gone_at_check)
          skip, limit = parse_pagination(args)
          value_filters = filters.slice(:search, :fields)
          history = store.list_by_record(**filters.except(*value_filters.keys), order: parse_sort(args))
          matched = withheld(context, args, history, gone_at_check).select do |entry|
            matches_value_filters?(entry, **value_filters)
          end

          [matched.drop(skip).first(limit), matched.size, -> { authors_of(matched) }]
        end

        # Asked again now, because the check above ran before these rows were read: a record deleted in
        # between answered "present and in scope" for rows that already carry its delete.
        def withheld(context, args, history, gone_at_check)
          withholding_scope = withholding_scope_for(context, context.collection, args[:params]['id'],
                                                    gone_at_check)

          withhold_out_of_scope_values(
            history, Withholding.new(context.collection, withholding_scope, context.caller.timezone)
          )
        end

        def matches_value_filters?(entry, search: nil, fields: nil)
          (search.nil? || search_matches?(entry, search)) && (fields.nil? || touches_field?(entry, fields))
        end

        # `Sql::TextSearch`'s test, on the served values: the term JSON-escaped the way the values serialize,
        # and a redacted mask removed before matching.
        def search_matches?(entry, term)
          text = term.downcase
          escaped = text.to_json[1..-2]

          ::ForestAdminAgent::AuditTrail::Sql::TextSearch::TEXT_COLUMNS.any? do |column|
            entry[column].to_s.downcase.include?(text)
          end || [entry.previous_values, entry.new_values].compact.any? do |values|
            values.to_json.gsub(::ForestAdminAgent::AuditTrail::Recording::REDACTED, '').downcase.include?(escaped)
          end
        end

        def touches_field?(entry, fields)
          [entry.previous_values, entry.new_values].compact.any? do |values|
            fields.any? { |field| values.key?(field) }
          end
        end

        def authors_of(entries)
          entries.reject { |entry| entry.user_id.nil? }
                 .map { |entry| ::ForestAdminAgent::AuditTrail::Store::AUTHOR_COLUMNS.to_h { |column| [column, entry[column]] } }
                 .uniq
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
