module ForestAdminDatasourcePylon
  module Pagination
    # Forest asks for an offset/limit window; Pylon only knows how to hand out
    # the next page of a cursor. Bridging the two means walking pages until the
    # window is covered, then slicing. Deep offsets therefore cost one request
    # per page, which is why the walk is capped: the requests are sequential —
    # a cursor is only known once the page before it came back — so an unbounded
    # walk is a list view the operator waits on, page after page, well before it
    # is a quota `/issues/search` grants 120 requests a minute of.
    class CursorWalker
      MAX_PAGES = 20
      MAX_RECORDS = 5_000

      def initialize(max_pages: MAX_PAGES, max_records: MAX_RECORDS)
        @max_pages = max_pages
        @max_records = max_records
      end

      # Yields `(limit, cursor)` and expects a Client::SearchPage back.
      #
      # A nil limit asks for every record past the offset: the walk then runs
      # until Pylon says there is no page left, or until a cap stops it. That
      # distinction is the whole point of accepting nil rather than a limit
      # standing in for "everything": a walk told to collect a thousand records
      # stops at a thousand having covered the window it was given, and reports
      # nothing, while a walk told to collect everything and stopped by a cap
      # knows it is handing back less than it was asked for, and says so.
      def walk(offset:, limit:)
        offset = offset.to_i.clamp(0, nil)
        limit = limit&.to_i
        return [] if limit && !limit.positive?

        needed = limit && (offset + limit)
        records = []
        cursor = nil
        pages = 0

        loop do
          page = yield(batch_size(needed, records.size), cursor)
          records.concat(page.records)
          pages += 1

          break if stop?(page, cursor)
          break if needed && records.size >= needed

          if capped?(pages, records.size)
            log_truncation(offset: offset, limit: limit, pages: pages, collected: records.size)
            break
          end

          cursor = page.next_cursor
        end

        limit ? (records[offset, limit] || []) : records.drop(offset)
      end

      private

      # An empty page or a cursor that does not move would loop forever; Pylon
      # does neither today, but a walk driven by a remote value stops on its own
      # terms rather than on the caps only.
      def stop?(page, cursor)
        page.next_cursor.nil? || page.records.empty? || page.next_cursor == cursor
      end

      def capped?(pages, collected)
        pages >= @max_pages || collected >= @max_records
      end

      # Bounded by the record budget left, and by the window still missing when
      # there is one, so the walk never collects past @max_records.
      def batch_size(needed, collected)
        budget = @max_records - collected
        budget = [needed - collected, budget].min if needed
        budget.clamp(1, Client::MAX_SEARCH_LIMIT)
      end

      def log_truncation(offset:, limit:, pages:, collected:)
        window = limit ? "offset=#{offset} limit=#{limit}" : "every record past offset=#{offset}"
        ForestAdminDatasourcePylon.logger.warn(
          "[forest_admin_datasource_pylon] Stopped paginating after #{pages} page(s) / #{collected} record(s) " \
          "while fetching #{window}; results are truncated. " \
          'Narrow the filter to reach records past this point.'
        )
      end
    end
  end
end
