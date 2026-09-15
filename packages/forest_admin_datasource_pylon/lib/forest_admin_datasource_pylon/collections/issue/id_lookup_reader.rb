module ForestAdminDatasourcePylon
  module Collections
    class Issue < BaseCollection
      # Reading issues named by their id, which Pylon serves one request at a
      # time: `POST /issues/search` cannot filter on id, so the short-circuit
      # `BaseCollection` extracts is answered by `GET /issues/{id}` per id.
      #
      # Split out of the collection for what it costs: everything here exists to
      # bound that fan-out, and none of it is about the shape of an issue.
      module IdLookupReader
        include RecordSerialization

        private

        # The records are already narrowed to the ids the filter asked for, so
        # applying the conditions left over by the short-circuit in memory
        # cannot return a record the API would have excluded. The reverse —
        # dropping a record over a condition memory evaluates differently from
        # Pylon — is ruled out by `extract_id_lookup`, which refuses such
        # residuals.
        #
        # Without a residual the ids are the answer, in order, so the window is
        # taken off them before any of them is read: one request per record the
        # caller asked to see, and none for the records it did not. A residual
        # takes that away — which records the window holds is only known once
        # they are all read — so past the cap the selection is refused rather
        # than answered with a fraction of itself.
        def records_by_id(caller, lookup, filter)
          return fetch_by_ids(page_of_ids(lookup.ids, filter)) if lookup.residual.nil?

          refuse_wide_lookup(lookup.ids.size) if lookup.ids.size > MAX_ID_LOOKUPS

          page_window(lookup.residual.apply(fetch_by_ids(lookup.ids), self, timezone_for(caller)), filter)
        end

        # The ids of the window, capped: `MAX_ID_LOOKUPS` bounds a page rather
        # than a selection here, a page being what each of these requests buys.
        def page_of_ids(ids, filter)
          offset, limit = translate_page(filter&.page)
          wanted = limit ? Array(ids[offset, limit]) : ids.drop(offset)
          capped = wanted.first(MAX_ID_LOOKUPS)
          warn_truncated_lookup(wanted.size) if wanted.size > capped.size

          capped
        end

        # `GET /issues/{id}` accepts the issue number as well as the UUID, so a
        # record answering with an id other than the one asked for is dropped:
        # see `matches_id?`.
        def fetch_by_ids(ids)
          ids.filter_map do |id|
            record = fetch_issue(id)
            next if record.nil?

            serialized = serialize(record)
            serialized if matches_id?(serialized, id)
          end
        end

        # A record the operator can no longer reach — deleted, or outside the
        # token's scope — reads as "no record" rather than as a failed page.
        def fetch_issue(id)
          datasource.client.fetch_issue(id)
        rescue APIError => e
          raise unless e.status == 404

          nil
        end

        def warn_truncated_lookup(asked)
          ForestAdminDatasourcePylon.logger.warn(
            "[forest_admin_datasource_pylon] Asked for a page of #{asked} issues by id, reading the first " \
            "#{MAX_ID_LOOKUPS}: Pylon answers one issue per request, and the requests are sequential. " \
            'Ask for a smaller page to reach the records past this point.'
          )
        end

        def refuse_wide_lookup(count)
          raise UnsupportedOperatorError,
                "This selection names #{count} issues by id and filters them further, which PylonIssue answers " \
                "with one request per named issue — more than the #{MAX_ID_LOOKUPS} one page covers. Reading " \
                'only some of them would drop records the other conditions keep, and silently answer a page ' \
                'that is missing them. Name fewer issues, or drop the other conditions.'
        end
      end
    end
  end
end
