module ForestAdminDatasourceIntercom
  module Collections
    class Ticket < CursorCollection
      # The two columns a support queue is read for and that Intercom does not
      # carry: when the ticket was closed, and who spoke last.
      #
      # A ticket has no `statistics` block -- measured against a workspace of 81
      # 142 tickets, confirming the specification -- so neither exists as a
      # field. Both are derived from the parts, and the parts arrive with the
      # search response whether or not anything asks for them, so both cost
      # nothing: this is the one place where deriving a column is cheaper than
      # reading one.
      #
      # Display only, and that is not a temporary state: `/tickets/search`
      # filters on neither and ignores a sort without reporting it, so a column
      # advertising either would put in the interface what the read cannot
      # honour.
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
          return unless (%w[closed_at closed_by_name] & projection).any?

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
          total ? total > parts_of(record).size : false
        end

        def last_closure(parts)
          closures = parts.select { |part| state_change?(part) && part['ticket_state'] == RESOLVED }

          closures.max_by { |part| part['created_at'].to_i }
        end

        # A part can record a transition to the state the ticket was already in
        # -- measured -- and that is not an event.
        def state_change?(part)
          part['part_type'].to_s.start_with?(STATE_CHANGE_PREFIX) &&
            part['ticket_state'] != part['previous_ticket_state']
        end

        def last_reply(parts)
          parts.select { |part| part['part_type'] == REPLY_PART }.max_by { |part| part['created_at'].to_i }
        end

        def author_of(part)
          author = (part || {})['author']
          author.is_a?(Hash) ? author : {}
        end

        def parts_of(record)
          nested_list((record || {})['ticket_parts'], 'ticket_parts')
        end

        def parts_total(record)
          container = (record || {})['ticket_parts']
          container.is_a?(Hash) ? container['total_count'] : nil
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
