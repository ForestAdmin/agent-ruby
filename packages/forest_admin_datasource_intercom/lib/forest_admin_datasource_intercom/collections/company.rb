module ForestAdminDatasourceIntercom
  module Collections
    # The accounts the contacts belong to.
    #
    # The one collection Intercom paginates by offset, and the one place R1 --
    # a window the API cannot express -- does not apply: `POST /companies/list`
    # takes a page number, which is what a list view asks for. See
    # `OffsetCollection`.
    #
    # In exchange it is the least filterable collection of the datasource.
    # There is no `/companies/search`, and what `GET /companies` answers is four
    # exact lookups: by `name`, by `company_id` -- the workspace's own
    # identifier, not Intercom's -- by `tag_id` and by `segment_id`. Two of them
    # are published as filters here, the two that name a column of this
    # collection; a tag and a segment are collections of their own and arrive
    # with lot 5, which is where filtering by them belongs.
    #
    # `GET /companies/scroll` is deliberately rejected rather than used: one
    # open scroll per application, expiring after a minute, cannot serve two
    # operators looking at a list at the same time.
    class Company < OffsetCollection
      include Company::Serializer
      include CustomAttributes

      # The column each lookup is written on, and the query parameter Intercom
      # answers it under. They happen to share a name; keeping the mapping
      # explicit is what lets a column be renamed without silently dropping the
      # lookup.
      LOOKUPS = { 'name' => 'name', 'company_id' => 'company_id' }.freeze

      def initialize(datasource, attributes: [])
        @attributes = attributes
        super(datasource, 'IntercomCompany')
      end

      protected

      def list_path = 'companies/list'
      def record_endpoint = 'companies'
      def lookups = LOOKUPS

      private

      def define_schema
        add_column('id', 'String', is_primary_key: true)
        # Intercom's id and the workspace's own are two different things, and an
        # ops team knows the second one: it is what their billing system calls
        # the account.
        add_column('company_id', 'String')
        add_column('name', 'String')
        define_profile_columns
        define_activity_columns
        # Before the attribute columns, so an attribute whose name lands on the
        # relation is skipped with a warning rather than taking the boot with
        # it.
        add_one_to_many('contacts', foreign_collection: 'IntercomContact', origin_key: 'company_id')
        register_attribute_columns
      end

      def define_profile_columns
        add_column('plan_name', 'String')
        add_column('size', 'Number')
        add_column('industry', 'String')
        add_column('website', 'String')
        add_column('monthly_spend', 'Number')
      end

      def define_activity_columns
        add_column('user_count', 'Number')
        add_column('session_count', 'Number')
        add_column('created_at', 'Date')
        add_column('updated_at', 'Date')
        add_column('last_request_at', 'Date')
        # When the account was created in the customer's own system, which is
        # not when Intercom heard about it.
        add_column('remote_created_at', 'Date')
      end

      # Typed from `GET /data_attributes?model=company`, and unfilterable for
      # the same reason as everything else here: this collection is looked up,
      # not searched.
      def attribute_kind = 'company'
    end
  end
end
