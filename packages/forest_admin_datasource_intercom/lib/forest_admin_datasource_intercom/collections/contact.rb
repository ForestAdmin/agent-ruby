module ForestAdminDatasourceIntercom
  module Collections
    # The people who write to the workspace: users and leads alike.
    #
    # Cursor-paginated like conversations and tickets, with one thing no other
    # collection of this datasource has -- **Intercom sorts it**.
    # `POST /contacts/search` is the only endpoint of the whole API that takes a
    # `sort` and applies it, so this is the only collection whose columns are
    # published sortable, and the measured table is what says which ones.
    #
    # Two routes of its own, on top of the three the tier already has:
    #
    # * a set of ids is read in one request -- `id IN [...]`, which this
    #   endpoint answers and no other does -- rather than one request per id;
    # * `company_id equals X` reads `GET /companies/{id}/contacts`, which is
    #   what serves the contacts of an account. `/contacts/search` filters no
    #   company field, so without this route the one relation an ops team walks
    #   the most would be a refusal.
    #
    # A contact merged into another **disappears** from the search and from the
    # listing: a row whose contact was merged reads as gone rather than as an
    # error, which is what a merge means -- the record still exists, under the
    # id it was merged into.
    # Long by line count only: most of it declares the columns, one call each.
    class Contact < CursorCollection # rubocop:disable Metrics/ClassLength
      include Contact::Serializer
      include CustomAttributes

      # `/contacts/search` demands a query, so a read with no condition of its
      # own -- a list view asking for an order -- sends the least noisy
      # predicate that matches everything. Every contact has a creation date,
      # and a bound at the epoch keeps whatever the day-granular truncation does
      # to it harmless. The same predicate `Ticket` sends, for the same reason.
      MATCH_EVERY_CONTACT = { 'field' => 'created_at', 'operator' => '>', 'value' => '0' }.freeze

      # How many ids one bulk read carries, and how many a single `id in [...]`
      # may name. Both are far above what a page asks for; they keep a scope or
      # a customizer naming thousands of ids from turning one list view into a
      # rate limit.
      IDS_PER_READ = 100
      MAX_IDS_READ = 300

      def initialize(datasource, attributes: [])
        @attributes = attributes
        super(datasource, 'IntercomContact')
        # Answered on the e-mail address, which is what an ops team types when
        # they are looking for someone. Per word, not as a substring -- see the
        # README.
        enable_search
      end

      # This endpoint answers `id IN [...]`, so a hundred ids cost one request
      # rather than a hundred: a relation pointing here resolves a whole page of
      # rows for a handful of requests, and there is no fan-out to refuse. That
      # is why `max_resolvable_ids` is nil where the other two tiers bound it --
      # the read is proportional to the rows already collected, and the walk
      # that collected them is bounded.
      def ids_per_read = IDS_PER_READ
      def max_resolvable_ids = nil

      protected

      def list_endpoint = 'contacts'
      def searchable = 'contacts'
      def search_column = 'email'
      def match_all_query = MATCH_EVERY_CONTACT
      def max_id_reads = MAX_IDS_READ

      private

      def define_schema
        add_column('id', 'String', is_primary_key: true)
        define_identity_columns
        define_date_columns
        define_reachability_columns
        define_device_columns
        # Before the attribute columns rather than after: a workspace attribute
        # whose name lands on a relation is then skipped with a warning, the way
        # one landing on a column already is. Declared after, it would collide
        # and take the boot with it.
        define_relations
        register_attribute_columns
      end

      def define_identity_columns
        add_column('role', 'String')
        add_column('name', 'String')
        add_column('email', 'String')
        add_column('email_domain', 'String')
        add_column('phone', 'String')
        add_column('external_id', 'String')
        add_column('avatar', 'String')
        add_column('owner_id', 'String')
        add_column('session_count', 'Number')
        # The first of the accounts the contact belongs to, and how many there
        # are: the same reading a conversation gives its contacts, and the
        # foreign key the `company` relation is built on.
        add_column('company_id', 'String')
        add_column('company_count', 'Number')
      end

      def define_date_columns
        add_column('created_at', 'Date')
        add_column('updated_at', 'Date')
        add_column('signed_up_at', 'Date')
        add_column('last_seen_at', 'Date')
        add_column('last_contacted_at', 'Date')
        add_column('last_replied_at', 'Date')
        add_column('last_email_opened_at', 'Date')
        add_column('last_email_clicked_at', 'Date')
      end

      def define_reachability_columns
        add_column('unsubscribed_from_emails', 'Boolean')
        add_column('has_hard_bounced', 'Boolean')
        add_column('marked_email_as_spam', 'Boolean')
      end

      def define_device_columns
        add_column('language_override', 'String')
        add_column('browser', 'String')
        add_column('browser_language', 'String')
        add_column('os', 'String')
        add_column('location_country', 'String')
        add_column('location_region', 'String')
        add_column('location_city', 'String')
      end

      # Typed from `GET /data_attributes?model=contact` rather than guessed from
      # a payload, and published unfilterable: which operators Intercom answers
      # on `custom_attributes.{name}` has not been measured, and this package
      # offers no filter it has not seen work. `api_writable` travels on the
      # introspected attribute for lot 4b, not on the column -- everything here
      # is read-only.
      def attribute_kind = 'contact'

      # The owner is a teammate, read whole in one request, and
      # `/contacts/search` filters on the key -- so that relation is readable,
      # navigable and filterable alike.
      #
      # The company is none of those last two: the endpoint filters no company
      # field, so the traversal is refused by name (see `check_relation_filterable!`
      # on the tier). The two lists are the 360 degrees this lot exists for.
      def define_relations
        add_many_to_one('owner', foreign_collection: 'IntercomAdmin', foreign_key: 'owner_id')
        add_many_to_one('company', foreign_collection: 'IntercomCompany', foreign_key: 'company_id')
        add_one_to_many('conversations', foreign_collection: 'IntercomConversation', origin_key: 'contact_id')
        add_one_to_many('tickets', foreign_collection: 'IntercomTicket', origin_key: 'contact_id')
      end

      # The contacts of an account, which `/contacts/search` cannot answer and
      # `GET /companies/{id}/contacts` can. Anything else goes the usual way.
      def fetch_records(caller, filter, sort = nil)
        company = company_lookup(filter)
        unless company
          refuse_narrowed_company!(filter) if narrowed_company?(filter)
          return super
        end

        warn_unordered_company_contacts(Array(filter&.sort)) if sort
        offset, limit = translate_page(filter&.page)

        walker.walk(offset: offset, limit: limit) do |per_page, cursor|
          read_company_page(company, per_page: per_page, cursor: cursor)
        end
      end

      def count_records(caller, filter)
        company = company_lookup(filter)
        unless company
          refuse_narrowed_company!(filter) if narrowed_company?(filter)
          return super
        end

        exact_count(read_company_page(company, per_page: 1, cursor: nil))
      end

      # A bare equality and nothing else: an `and` also carrying a scope names a
      # narrower set than the account does, and answering it with the account
      # alone would serve contacts the scope excludes.
      def company_lookup(filter)
        tree = filter&.condition_tree
        return nil unless tree.is_a?(Leaf) && tree.field.to_s == 'company_id'
        return nil unless tree.operator == Operators::EQUAL && blank_search?(filter)

        tree.value&.to_s
      end

      # The same equality, and something filtered alongside it. There is no
      # request that answers both halves: `GET /companies/{id}/contacts` narrows
      # nothing it returns, and `/contacts/search` filters no company field at
      # all -- which is what the related list of an account runs into the moment
      # a permission scope or a segment is defined on this collection.
      #
      # Refused here rather than left to the translator, whose reason for
      # `company_id` is "open the company and read its contacts" -- which is
      # exactly what this caller was doing.
      def narrowed_company?(filter)
        tree = filter&.condition_tree
        return false if tree.nil? || tree.is_a?(Leaf)

        tree.some_leaf { |leaf| leaf.field.to_s == 'company_id' && leaf.operator == Operators::EQUAL }
      end

      def refuse_narrowed_company!(filter)
        raise UnsupportedOperatorError,
              "#{name} cannot answer this filter: the contacts of an account are read through " \
              'GET /companies/{id}/contacts, which returns them whole and narrows nothing, and ' \
              "#{search_endpoint.path} filters no company field -- so the account and the " \
              "#{narrowing_cause(filter)} cannot be asked for in one request. Read the account's contacts " \
              'without it, or filter on a column this collection is searched on: ' \
              "#{search_endpoint.filterable_columns.join(", ")}."
      end

      # A scope and a segment are what put a condition next to the account's in
      # practice, and the operator can act on neither the same way -- so the
      # message names what it can see rather than guessing.
      def narrowing_cause(filter)
        others = []
        filter.condition_tree.some_leaf do |leaf|
          others << leaf.field.to_s unless leaf.field.to_s == 'company_id'
          false
        end

        others.empty? ? 'condition filtered alongside it' : "condition on #{others.uniq.join(", ")}"
      end

      # An account Intercom no longer answers for -- deleted, or moved outside
      # the token's reach between the moment the row was rendered and the
      # moment its related list was opened -- reads as an account with no
      # contact rather than as a failed page, the way a record read by its id
      # already does.
      def read_company_page(company, per_page:, cursor:)
        client.list_page("companies/#{Faraday::Utils.escape(company)}/contacts",
                         per_page: [per_page, max_page_size].min, starting_after: cursor)
      rescue APIError => e
        raise unless e.status == 404

        Client::Page.new(records: [], next_cursor: nil, total_count: 0)
      end

      # One request per hundred ids instead of one per id: this endpoint answers
      # `id IN [...]`, which is what lot 1 already reads the contacts of a page
      # through. A contact that was merged away is simply absent from the
      # answer -- the row reads as gone, not as a failure.
      def records_by_ids(ids)
        wanted = ids.first(max_id_reads)
        warn_truncated_ids(ids.size) if ids.size > wanted.size

        wanted.each_slice(IDS_PER_READ).flat_map do |chunk|
          client.search_page(search_endpoint.path, per_page: chunk.size,
                                                   query: { 'field' => 'id', 'operator' => 'IN',
                                                            'value' => chunk }).records
        end
      end

      # `sort` here is the clause `server_sort` found `/contacts/search` does
      # honour, which is why nothing has reported it yet: it is this route that
      # cannot carry the order, not the column. Saying Intercom does not sort
      # this collection would be wrong -- it is the one collection it sorts --
      # so this is the counterpart of `warn_unordered_ids`, for the other route
      # that leaves the search behind.
      def warn_unordered_company_contacts(clauses)
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] #{name} was asked to sort on " \
          "#{clauses.map { |clause| sort_field(clause) }.join(", ")} while reading the contacts of an account, " \
          'which Intercom answers through GET /companies/{id}/contacts -- a route that takes no order, unlike ' \
          'the search this collection is otherwise read through. The rows come back in the order the API imposes.'
        )
      end

      def warn_truncated_ids(asked)
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] #{name} was asked for #{asked} records by id and read the first " \
          "#{max_id_reads}: Intercom reads them #{IDS_PER_READ} at a time. The result is truncated."
        )
      end
    end
  end
end
