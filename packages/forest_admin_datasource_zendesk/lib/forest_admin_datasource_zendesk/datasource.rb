module ForestAdminDatasourceZendesk
  class Datasource < ForestAdminDatasourceToolkit::Datasource
    attr_reader :client, :configuration

    def initialize(subdomain:, username:, token:)
      super()
      @configuration = Configuration.new(subdomain: subdomain, username: username, token: token)
      @client = Client.new(@configuration)

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

      register_custom_field_translations(ticket_cf, user_cf, org_cf)
    end

    # The translator needs the (Forest column → Zendesk search field) mapping
    # to translate filters on custom fields. We hand it the merged set so any
    # filter on a custom column resolves to the right search syntax.
    def register_custom_field_translations(ticket_cf, user_cf, org_cf)
      mapping = {}
      ticket_cf.each { |cf| mapping[cf[:column_name]] = "custom_field_#{cf[:zendesk_id]}" }
      # User/org custom fields are addressed by key in Zendesk Search.
      (user_cf + org_cf).each do |cf|
        next unless cf[:zendesk_key]

        mapping[cf[:column_name]] ||= cf[:zendesk_key]
      end

      ForestAdminDatasourceZendesk::Query::ConditionTreeTranslator.custom_field_mapping = mapping
    end
  end
end
