module ForestAdminDatasourceIntercom
  module Pagination
    # Intercom only paginates by cursor (no jump to page N), so an offset/limit window costs one sequential
    # request per page. Capped for operator patience (R9), and every truncation is logged, never silent.
    class CursorWalker
      # 50 pages of 150 records. Intercom's quota lets these be generous: the
      # walk is bounded by patience, and by the point past which a list view is
      # not being read but scraped.
      MAX_PAGES = 50
      MAX_RECORDS = 7_500

      def initialize(max_pages: MAX_PAGES, max_records: MAX_RECORDS)
        @max_pages = max_pages
        @max_records = max_records
      end

      # Yields `(per_page, cursor)` and expects a Client::Page back. A nil limit means every record past
      # the offset, so a cap stopping the walk is known to be a truncation and is logged.
      def walk(offset:, limit:, &page_source)
        offset = offset.to_i.clamp(0, nil)
        limit = limit&.to_i
        return [] if limit && !limit.positive?

        records = collect(offset, limit, &page_source)

        limit ? (records[offset, limit] || []) : records.drop(offset)
      end

      private

      # The walk itself: pages are collected until the window is covered, the
      # source says there is nothing left, or a cap stops it. The slicing is
      # `walk`'s; this only decides how far to go.
      def collect(offset, limit)
        needed = limit && (offset + limit)
        records = []
        cursor = nil
        seen_ids = Set.new
        seen_cursors = Set.new
        pages = 0

        loop do
          page = yield(batch_size(needed, records.size), cursor)
          records.concat(fresh(page.records, seen_ids))
          pages += 1

          # The only silent exits: Intercom said there is no page left, or the
          # window asked for is covered. Everything below hands back less than
          # was asked for, and says so.
          break if page.next_cursor.nil?
          break if needed && records.size >= needed
          break if cut_short?(page, seen_cursors, pages, records: records.size, window: window_of(offset, limit))

          cursor = page.next_cursor
        end

        records
      end

      # Whether the walk is handing back less than it was asked for, and which
      # of the two reasons it is. Both are logged here rather than by the
      # caller: a page that looks like the whole answer and is not is the
      # failure this datasource exists to avoid, so there is no route out of
      # this walk that is short and quiet.
      def cut_short?(page, seen_cursors, pages, records:, window:)
        if stalled?(page, seen_cursors)
          log_stalled(window: window, pages: pages, collected: records)
        elsif capped?(pages, records)
          log_truncation(window: window, pages: pages, collected: records)
        else
          return false
        end

        true
      end

      # Intercom documents duplicate or missed records when items change mid-walk; duplicates are dropped
      # here (missed ones cannot be). A record with no id is kept.
      def fresh(records, seen_ids)
        records.select { |record| record['id'].nil? || seen_ids.add?(record['id']) }
      end

      # An empty page with a next cursor, or a cursor already followed: Intercom does neither today, but a
      # walk driven by a remote value must stop on its own terms -- and the stop is logged as a truncation.
      def stalled?(page, seen_cursors)
        page.records.empty? || !seen_cursors.add?(page.next_cursor)
      end

      def capped?(pages, collected)
        pages >= @max_pages || collected >= @max_records
      end

      # Bounded by the record budget left, and by the window still missing when
      # there is one, so the walk never collects past @max_records. `Client`
      # bounds it again to what Intercom accepts.
      def batch_size(needed, collected)
        budget = @max_records - collected
        budget = [needed - collected, budget].min if needed
        Client.bounded_per_page(budget)
      end

      def log_truncation(window:, pages:, collected:)
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] Stopped paginating after #{pages} page(s) / " \
          "#{collected} record(s) while fetching #{window}; results are truncated. " \
          'Narrow the filter to reach records past this point.'
        )
      end

      def log_stalled(window:, pages:, collected:)
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] Stopped paginating after #{pages} page(s) / " \
          "#{collected} record(s) while fetching #{window}: Intercom advertised a next page this could not " \
          'follow -- an empty page, or a cursor already read. Results are truncated.'
        )
      end

      def window_of(offset, limit)
        limit ? "offset=#{offset} limit=#{limit}" : "every record past offset=#{offset}"
      end
    end
  end
end
