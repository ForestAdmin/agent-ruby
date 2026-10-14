module ForestAdminAgent
  module Routes
    module Resources
      # The project-level timeline, mirroring the Node agent's `GET /_audit-trail`: every readable collection's
      # audit rows in one walk, paged by an inclusive cursor rather than by page number, since the front merges
      # it with the activity logs and no count spans both.
      #
      # Values are served as on the per-record history: a caller who can read a collection reads its rows'
      # values. Who may open the project's Activity Logs page at all is Forest's to decide, not the agent's.
      class AuditTrailTimeline < AbstractAuthenticatedRoute
        include AuditTrailRoute
        include AuditTrailQueryParams

        def setup_routes
          return self unless store

          add_route('forest_audit_trail_timeline', 'get', '/_audit-trail', ->(args) { handle_request(args) })

          self
        end

        def handle_request(args = {})
          context = build(args)
          order = args.dig(:params, 'sort').to_s == 'timestamp' ? 'asc' : 'desc'
          limit = parse_page_size(args)
          cursor = parse_cursor(args, order)
          # Parsed before the permission sweep, so a malformed filter reads as a 400 whatever the caller may
          # see. No `fields`: a column name means nothing across collections.
          filters = parse_filters(args).except(:fields)
          collections = readable_collections(context).map(&:name)

          # One row over the page: the only way to know whether a further page exists without a count.
          fetched = store.list_timeline(**filters, **cursor, order: order, collections: collections,
                                                             limit: limit + 1)
          page = fetched.first(limit)
          meta = { cursor: fetched.size > limit ? next_cursor(page, cursor, order) : nil }
          # Authors on the first page only, like the per-record route: they do not change along the walk, and
          # later pages omit the key rather than send `[]`.
          if cursor[:before].nil? && cursor[:after].nil?
            meta[:availableUsers] = store.timeline_users(**filters, collections: collections)
                                         .map { |author| available_user(author) }
          end

          { content: { data: page.map { |record| serialize_record(record) }, meta: meta } }
        end

        private

        # A record-level scope cannot be evaluated across a whole timeline without fetching every record it
        # mentions, so a collection the caller only sees through one is left out entirely rather than served
        # unfiltered: the row alone would say that a record they cannot read exists and was touched.
        def readable_collections(context)
          context.permissions.allowed_collections(:read, context.datasource.collections.values)
                 .select { |collection| context.permissions.get_scope(collection).nil? }
        end

        # `before` (`after` oldest first) is an inclusive bound, so the rows sharing the last row's timestamp are
        # carried as `excludeIds` rather than skipped. When the previous page ended on the same timestamp its
        # exclusions still apply, so a timestamp holding more rows than one page walks on instead of looping.
        # Nil when the walk would not progress: staying on the same timestamp must exclude at least one more id.
        def next_cursor(page, previous, order)
          bound = order == 'asc' ? :after : :before
          last = page.last
          same_boundary = previous[bound] && same_instant?(previous[bound], last.timestamp)
          carried = same_boundary ? previous[:exclude_ids] : []
          tied = page.select { |row| same_instant?(row.timestamp, last.timestamp) }.map(&:id)
          exclude_ids = (carried + tied).uniq

          return nil if same_boundary && exclude_ids.size == carried.size

          { bound => last.timestamp, excludeIds: exclude_ids }
        end

        def same_instant?(one, other)
          Time.iso8601(one.to_s) == Time.iso8601(other.to_s)
        end

        # The bound is the timestamp of a row this route served, so it is an ISO instant; only the one for the
        # walk's direction is read.
        def parse_cursor(args, order)
          bound = order == 'asc' ? :after : :before
          raw = args.dig(:params, bound.to_s).to_s
          exclude_ids = args.dig(:params, 'excludeIds').to_s.split(',').map(&:strip).grep(/\A\d+\z/).map(&:to_i)

          { bound => raw.empty? ? nil : parse_instant(raw), exclude_ids: exclude_ids }
        end

        def parse_instant(raw)
          Time.iso8601(raw).utc.iso8601(3)
        rescue ArgumentError
          raise Http::Exceptions::ValidationError, "Invalid cursor: \"#{raw}\" (expected an ISO 8601 instant)"
        end
      end
    end
  end
end
