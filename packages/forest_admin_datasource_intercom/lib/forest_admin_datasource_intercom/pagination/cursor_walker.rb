module ForestAdminDatasourceIntercom
  module Pagination
    # Forest asks for an offset/limit window; Intercom only knows how to hand
    # out the page after a cursor, and documents that jumping to page N is not
    # supported. Bridging the two means walking pages until the window is
    # covered, then slicing it out. Reaching page 20 therefore costs 20
    # requests -- sequential ones, a cursor only being known once the page
    # before it came back.
    #
    # The walk is capped for that reason rather than for the quota's: 10 000
    # requests a minute is generous enough that the caps below are about what an
    # operator is willing to wait for, and about the fact that page 200 of a
    # list view answers no real question (R9). Every truncation is logged --
    # never silent, since a page that looks like the whole answer and is not is
    # the failure this datasource exists to avoid.
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

      # Yields `(per_page, cursor)` and expects a Client::Page back.
      #
      # A nil limit asks for every record past the offset: the walk then runs
      # until Intercom says there is no page left, or until a cap stops it. That
      # distinction is the whole point of accepting nil rather than a huge limit
      # standing in for "everything": a walk told to collect a thousand records
      # stops at a thousand having covered the window it was given, and reports
      # nothing, while a walk told to collect everything and stopped by a cap
      # knows it is handing back less than it was asked for, and says so.
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

      # Intercom documents that "if items are modified between paginated
      # requests it is possible to see duplicate or missed records" -- and
      # conversations move constantly, so a deep walk over them will see the
      # same record twice. A duplicate is dropped here rather than being served
      # as two rows carrying one id, which is what a list view would render as
      # two identical lines and a record count that never adds up. The missing
      # counterpart is inherent to cursor pagination and is documented instead.
      #
      # A record with no id is kept: it is not this walk's business to decide
      # that a payload it does not recognise is not a record.
      def fresh(records, seen_ids)
        records.select { |record| record['id'].nil? || seen_ids.add?(record['id']) }
      end

      # A page that advertises a next cursor and holds nothing, and a cursor
      # already followed. Intercom does neither today -- `pages.next` is simply
      # absent on the last page -- but a walk driven by a remote value stops on
      # its own terms rather than on the caps only: a cycle wider than one page
      # would otherwise collect the same pages until a cap cut it short.
      #
      # Which is exactly why it is reported. Stopping here means Intercom said
      # there was more and this could not follow it, so the answer is short of
      # what was asked -- a truncation like the caps below, and the same rule
      # applies: never silent.
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
