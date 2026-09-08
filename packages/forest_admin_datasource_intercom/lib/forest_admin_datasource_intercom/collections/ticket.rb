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
      include CustomAttributes
      # The same thread a conversation publishes, and free here: the parts are
      # in the response whether or not anything asks for them.
      include Timeline

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

      def record_endpoint = 'tickets'
      def list_key = 'tickets'
      def searchable = 'tickets'
      def max_page_size = MAX_TICKETS_PER_PAGE

      # The part bodies are HTML written by end customers, and rendering
      # third-party HTML inside Forest is neither safe nor useful (R10). Sent on
      # the search, where Intercom does not document it: a parameter it ignores
      # costs a query string, while the one it honours saves every row of the
      # thread from coming back as markup.
      def read_params = { 'display_as' => 'plaintext' }

      # Intercom exposes no `GET /tickets`, so a list view searches too: with the
      # filter it was given, or with the predicate that matches everything when
      # it was given none.
      def searchable_only? = true
      def match_all_query = MATCH_EVERY_TICKET

      def enrich(records, rows, projection)
        wanted = Array(projection).map(&:to_s)

        embed_contact_identity(records, rows, wanted)
        embed_derived_columns(records, rows, wanted)
        embed_timeline(records, rows, wanted)
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
        add_column('timeline', 'Json')
        # Before the attribute columns rather than after: a workspace attribute
        # whose name lands on a relation is then skipped with a warning, the way
        # one landing on a column already is. Declared after, it would collide
        # and take the boot with it.
        define_relations
        register_attribute_columns
      end

      # The state arrives embedded as a whole object, so its label costs nothing:
      # a queue reads without a join. One label and not three -- the category and
      # the customer-facing label are read through the `state` relation, which is
      # where every field of a state lives. Neither of the two was ever
      # filterable, so nothing that could be saved in a segment or a scope
      # depended on them.
      def define_state_columns
        add_column('state_id', 'String')
        add_column('state_label', 'String')
        add_column('previous_state_id', 'String')
      end

      def define_type_columns
        add_column('ticket_type_id', 'String')
        add_column('ticket_type_name', 'String')
      end

      # The reference collections a ticket points at, and the contact who opened
      # it. Every reference target is read whole in one request, so those
      # relations resolve for a page at the price of a single read; the contact
      # is read from `/contacts/search`, one request for the page as well.
      #
      # Which of them can be filtered *through* is the measured table's
      # business, not this method's: `/tickets/search` takes a filter on
      # `admin_assignee_id`, `team_assignee_id` and `ticket_type_id`, none on a
      # state id, and `contact_ids` is a `spec` row the probe has yet to
      # confirm. Where the endpoint filters nothing, the traversal is refused by
      # name rather than left for the interface to offer and the API to drop.
      def define_relations
        add_many_to_one('admin_assignee', foreign_collection: 'IntercomAdmin', foreign_key: 'admin_assignee_id')
        add_many_to_one('team_assignee', foreign_collection: 'IntercomTeam', foreign_key: 'team_assignee_id')
        add_many_to_one('state', foreign_collection: 'IntercomTicketState', foreign_key: 'state_id')
        add_many_to_one('previous_state', foreign_collection: 'IntercomTicketState',
                                          foreign_key: 'previous_state_id')
        add_many_to_one('ticket_type', foreign_collection: 'IntercomTicketType', foreign_key: 'ticket_type_id')
        add_many_to_one('contact', foreign_collection: 'IntercomContact', foreign_key: 'contact_id')
      end

      # Costs no request, unlike a conversation's: Intercom returns the parts of
      # a ticket in the search response and offers no way to ask it not to, so
      # the page pays for them whatever the projection says. Building the thread
      # out of them is what is guarded here.
      #
      # An empty list means an empty thread, and says so -- where a conversation
      # read from a listing carries no parts at all and its timeline stays nil,
      # which reads as unknown.
      def embed_timeline(records, rows, projection)
        return unless projection.include?('timeline')

        records.each_with_index { |record, index| rows[index]['timeline'] = build_timeline(record) }
      end

      # The attribute columns of every ticket type, in union. Read at boot by
      # `TicketAttributesIntrospector`, which is also where a workspace's own
      # name is turned into one a Forest query string can carry.
      def attribute_kind = 'ticket'
    end
  end
end
