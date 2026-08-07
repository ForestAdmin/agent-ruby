module ForestAdminDatasourcePylon
  module Pagination
    # Forest asks for an offset/limit window; Pylon only knows how to hand out
    # the next page of a cursor. Bridging the two means walking pages until the
    # window is covered, then slicing. Deep offsets therefore cost one request
    # per page, which is why the walk is capped: `/issues/search` allows 20
    # requests per minute, so an unbounded walk would spend the whole budget of
    # the agent on a single list view.
    class CursorWalker
      MAX_PAGES = 20
      MAX_RECORDS = 5_000

      def initialize(max_pages: MAX_PAGES, max_records: MAX_RECORDS)
        @max_pages = max_pages
        @max_records = max_records
      end

      # Yields `(limit, cursor)` and expects a Client::SearchPage back.
      def walk(offset:, limit:)
        return [] unless limit.to_i.positive?

        needed = offset.to_i + limit.to_i
        records = []
        cursor = nil
        pages = 0

        loop do
          page = yield(batch_size(needed - records.size), cursor)
          records.concat(page.records)
          pages += 1

          break if stop?(page, cursor) || records.size >= needed

          if capped?(pages, records.size)
            log_truncation(offset: offset, limit: limit, pages: pages, collected: records.size)
            break
          end

          cursor = page.next_cursor
        end

        records[offset.to_i, limit.to_i] || []
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

      def batch_size(remaining)
        remaining.clamp(1, Client::MAX_SEARCH_LIMIT)
      end

      def log_truncation(offset:, limit:, pages:, collected:)
        ForestAdminDatasourcePylon.logger.warn(
          "[forest_admin_datasource_pylon] Stopped paginating after #{pages} page(s) / #{collected} record(s) " \
          "while fetching offset=#{offset} limit=#{limit}; results are truncated. " \
          'Narrow the filter to reach records past this point.'
        )
      end
    end
  end
end
