module ForestAdminDatasourceIntercom
  module Collections
    class Ticket < CursorCollection
      # Derived from the parts: a ticket has no `statistics` block (measured on 81 142 tickets). Display only
      # for good: /tickets/search filters on neither and silently ignores a sort on them.
      module DerivedColumns
        # A ticket is not "closed" on Intercom, it enters a state whose category
        # is resolved.
        RESOLVED = 'resolved'.freeze

        # Matched on the prefix, never on the full `ticket_state_updated_by_admin`
        # the sample showed: a workspace running workflows closes tickets through
        # other variants of the same event, and a closure nobody can see is worse
        # than a column nobody offers.
        STATE_CHANGE_PREFIX = 'ticket_state_updated'.freeze

        # A reply to the customer. A `note` is an internal touch, not an answer:
        # counting it would name as "last responder" someone who never wrote to
        # the person waiting.
        REPLY_PART = 'comment'.freeze

        # The columns a truncated timeline leaves unknown rather than empty, and
        # therefore the ones whose presence in a projection is worth a warning.
        CLOSURE_COLUMNS = %w[closed_at closed_by_name].freeze

        private

        def define_derived_columns
          add_column('closed_at', 'Date')
          add_column('closed_by_name', 'String')
          add_column('last_reply_at', 'Date')
          add_column('last_responder_name', 'String')
          # `admin` or `contact`: whether the last word came from the team or
          # from the customer is what tells a queue who owes the next one.
          add_column('last_responder_type', 'String')
        end

        def derived_columns_for(attrs)
          parts = parts_of(attrs)
          closure = last_closure(parts)
          reply = last_reply(parts)

          { 'closed_at' => stamp(closure&.dig('created_at')),
            'closed_by_name' => author_of(closure)['name'],
            'last_reply_at' => stamp(reply&.dig('created_at')),
            'last_responder_name' => author_of(reply)['name'],
            'last_responder_type' => author_of(reply)['type'] }
        end

        # The hook of the base's `enrich`: nothing to read here, since
        # `serialize` already derived everything. What is left is telling the
        # operator when a value is missing because the timeline was truncated
        # rather than because the event never happened.
        def embed_derived_columns(records, _rows, projection)
          return unless any_column_asked?(projection, CLOSURE_COLUMNS)

          unknown = records.count { |record| closure_unknown?(record) }
          warn_unknown_closures(unknown) if unknown.positive?
        end

        # A resolved ticket with no closure in hand, on a timeline Intercom
        # truncated: the date is *unknown*, not absent. A Date column cannot say
        # that, so the log does.
        def closure_unknown?(record)
          state = record['ticket_state'].is_a?(Hash) ? record['ticket_state'] : {}
          return false unless state['category'] == RESOLVED

          last_closure(parts_of(record)).nil? && truncated?(record)
        end

        # Intercom keeps the 500 most recent parts of a ticket. Past that, the
        # transition that closed it may have fallen out of the window.
        def truncated?(record)
          total = parts_total(record)
          total ? total > Array(parts_of(record)).size : false
        end

        def last_closure(parts)
          closures = Array(parts).select { |part| state_change?(part) && part['ticket_state'] == RESOLVED }

          closures.max_by { |part| part['created_at'].to_i }
        end

        # A part can record a transition to the state the ticket was already in
        # -- measured -- and that is not an event.
        def state_change?(part)
          part['part_type'].to_s.start_with?(STATE_CHANGE_PREFIX) &&
            part['ticket_state'] != part['previous_ticket_state']
        end

        def last_reply(parts)
          Array(parts).select { |part| part['part_type'] == REPLY_PART }.max_by { |part| part['created_at'].to_i }
        end

        def author_of(part)
          author = (part || {})['author']
          author.is_a?(Hash) ? author : {}
        end

        # nil rather than an empty list when the payload carries no parts: an
        # empty thread would read as a ticket nothing happened to.
        def parts_of(record)
          container = (record || {})['ticket_parts']
          parts = container['ticket_parts'] if container.is_a?(Hash)
          parts.is_a?(Array) ? parts : nil
        end

        def parts_total(record)
          container = (record || {})['ticket_parts']
          container.is_a?(Hash) ? container['total_count'] : nil
        end

        def warn_truncated_timelines(truncated)
          ForestAdminDatasourceIntercom.logger.warn(
            "[forest_admin_datasource_intercom] #{name}: the timeline of #{truncated} ticket(s) of this page " \
            'holds only their 500 most recent parts, Intercom keeping no more. Earlier events are left out.'
          )
        end

        def warn_unknown_closures(unknown)
          ForestAdminDatasourceIntercom.logger.warn(
            "[forest_admin_datasource_intercom] #{name}: #{unknown} resolved ticket(s) of this page show no " \
            'closure date because Intercom truncated their timeline at 500 parts, not because they were never ' \
            'closed. The column is unknown for those rows.'
          )
        end
      end
    end
  end
end
