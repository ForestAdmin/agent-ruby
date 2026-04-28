module ForestAdminDatasourceZendesk
  class Datasource < ForestAdminDatasourceToolkit::Datasource
    attr_reader :client, :configuration, :custom_field_mapping

    def initialize(subdomain:, username:, token:)
      super()
      @configuration = Configuration.new(subdomain: subdomain, username: username, token: token)
      @client = Client.new(@configuration)
      @custom_field_mapping = {}

      register_collections
    end

    private

    def register_collections
      introspector = Schema::CustomFieldsIntrospector.new(@client)

      ticket_cf = introspector.ticket_custom_fields
      user_cf   = introspector.user_custom_fields
      org_cf    = introspector.organization_custom_fields

      add_collection(Collections::Ticket.new(self, custom_fields: ticket_cf))
      add_collection(Collections::User.new(self, custom_fields: user_cf))
      add_collection(Collections::Organization.new(self, custom_fields: org_cf))
      add_collection(Collections::Comment.new(self))

      @custom_field_mapping = build_custom_field_mapping(ticket_cf, user_cf, org_cf)
    end

    # Forest column name -> Zendesk Search field name. The mapping lives on
    # the Datasource instance (not on the translator class) so multi-tenant
    # agents with multiple Zendesk datasources don't trample each other.
    # The collections pass it through to ConditionTreeTranslator.call(...).
    def build_custom_field_mapping(ticket_cf, user_cf, org_cf)
      mapping = {}
      ticket_cf.each { |cf| mapping[cf[:column_name]] = "custom_field_#{cf[:zendesk_id]}" }
      # User / org custom fields are addressed by key in Zendesk Search.
      (user_cf + org_cf).each do |cf|
        next unless cf[:zendesk_key]

        mapping[cf[:column_name]] ||= cf[:zendesk_key]
      end
      mapping
    end
  end
end
