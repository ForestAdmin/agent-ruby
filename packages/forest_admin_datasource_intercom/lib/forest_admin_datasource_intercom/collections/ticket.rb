module ForestAdminDatasourceIntercom
  module Collections
    # The tickets of the workspace.
    #
    # Read through `POST /tickets/search`: Intercom exposes no `GET /tickets` at
    # all, so even an unfiltered list view goes through the search endpoint with
    # a predicate that matches everything. Its records come back under `tickets`
    # rather than under the `data` envelope -- measured.
    #
    # The response carries the whole timeline of every ticket, and there is no
    # way to ask it not to: Intercom offers no field selection. Measured, one
    # ticket carried 155 parts, so a page of 150 would move some 23 000 part
    # objects, customer message bodies included. Two consequences run through
    # this class: the page size is bounded far below what the API accepts, and
    # everything derived from those parts is free, since they are paid for
    # whether or not anything asks.
    class Ticket < CursorCollection
      include ContactIdentity
      include Ticket::Serializer
      include Ticket::DerivedColumns

      # Intercom accepts 150. This is not that: it is what keeps one page of
      # tickets, timelines included, a response an agent can hold and an operator
      # can wait for. Provisional until measured against real response sizes on
      # the customer's workspace.
      MAX_TICKETS_PER_PAGE = 25

      # `/tickets/search` demands a query, so a list view sends the least noisy
      # predicate that matches everything. Every ticket has a creation date, and
      # a bound at the epoch keeps whatever the day-granular truncation does to
      # it harmless.
      MATCH_EVERY_TICKET = { 'field' => 'created_at', 'operator' => '>', 'value' => '0' }.freeze

      def initialize(datasource, attributes: [])
        @attributes = attributes
        super(datasource, 'IntercomTicket')
      end

      protected

      def list_endpoint = 'tickets/search'
      def record_endpoint = 'tickets'
      def list_key = 'tickets'
      def max_page_size = MAX_TICKETS_PER_PAGE

      # A search rather than a listing, which is the whole reason this hook
      # exists.
      def read_page(per_page:, cursor:)
        client.search_page(list_endpoint, query: MATCH_EVERY_TICKET, list_key: list_key,
                                          per_page: [per_page, max_page_size].min, starting_after: cursor)
      end

      def enrich(records, rows, projection)
        wanted = Array(projection).map(&:to_s)

        embed_contact_identity(records, rows, wanted)
        embed_derived_columns(records, rows, wanted)
      end

      private

      def define_schema
        add_column('id', 'String', is_primary_key: true)
        # The number the support team says out loud, next to the id the API
        # answers by.
        add_column('ticket_id', 'String')
        # `request` / `task` / `tracker` on the wire, never the labels the
        # Intercom interface shows -- the same mismatch a filter on it will have
        # to respect.
        add_column('category', 'String')
        add_column('open', 'Boolean')
        add_column('is_shared', 'Boolean')
        add_column('created_at', 'Date')
        add_column('updated_at', 'Date')
        add_column('admin_assignee_id', 'String')
        add_column('team_assignee_id', 'String')
        # The ticket carries its company as an id alone, unlike a conversation
        # which carries the whole object: the account name would cost a request
        # per row, so it is not offered here. Measured: the id is Intercom's own,
        # not the customer's external one, which is what a relation will have to
        # target in lot 4.
        add_column('company_id', 'String')
        define_state_columns
        define_type_columns
        define_contact_columns
        define_derived_columns
        add_column('part_count', 'Number')
        register_attribute_columns
      end

      # The state arrives embedded as a whole object, so its labels cost nothing.
      # `IntercomTicketState` remains a collection of its own -- it is the list of
      # what a state can be -- but a row does not depend on it to be readable.
      def define_state_columns
        add_column('state_id', 'String')
        add_column('state_category', 'String')
        add_column('state_label', 'String')
        add_column('state_external_label', 'String')
        add_column('previous_state_id', 'String')
      end

      def define_type_columns
        add_column('ticket_type_id', 'String')
        add_column('ticket_type_name', 'String')
      end

      # The attribute columns of every ticket type, in union. Read at boot by
      # `TicketAttributesIntrospector`; an attribute whose name is already a
      # column of this collection is skipped rather than silently overwriting it.
      def register_attribute_columns
        @attribute_columns = @attributes.reject { |attribute| collides?(attribute) }
        @attribute_columns.each { |attribute| add_column(attribute.name, attribute.column_type) }
      end

      def collides?(attribute)
        return false unless fields.key?(attribute.name)

        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] #{name} skips the ticket attribute '#{attribute.name}': a native " \
          'column already carries that name, and overwriting it would show the attribute where the operator ' \
          'expects the ticket field.'
        )
        true
      end

      def attribute_columns
        @attribute_columns || []
      end
    end
  end
end
