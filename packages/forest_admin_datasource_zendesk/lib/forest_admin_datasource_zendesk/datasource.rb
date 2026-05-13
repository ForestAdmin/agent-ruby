module ForestAdminDatasourceZendesk
  class Datasource < ForestAdminDatasourceToolkit::Datasource
    attr_reader :client, :configuration, :custom_field_mapping,
                :default_ticket_subject, :default_ticket_message, :requester_email_default,
                :default_ticket_action_name, :email_templates,
                :priority_override, :type_override,
                :close_ticket_statuses

    def initialize(subdomain:, username:, token:, **opts)
      super()
      @configuration = Configuration.new(subdomain: subdomain, username: username, token: token)
      @client = Client.new(@configuration)
      @custom_field_mapping = {}
      @default_ticket_subject     = opts[:default_ticket_subject]
      @default_ticket_message     = opts[:default_ticket_message]
      @requester_email_default    = opts[:requester_email_default]
      @default_ticket_action_name = opts[:default_ticket_action_name]
      @email_templates            = Array(opts[:email_templates]).compact
      @priority_override          = opts[:priority_override]
      @type_override              = opts[:type_override]
      @close_ticket_statuses      = Array(opts[:close_ticket_statuses]).map(&:to_s).uniq

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

      @custom_field_mapping = build_custom_field_mapping(ticket_cf, user_cf, org_cf)
    end

    # Forest column name -> Zendesk Search field name. Lives on the instance
    # (not the translator class) so multiple Zendesk datasources in the same
    # agent don't share state.
    def build_custom_field_mapping(ticket_cf, user_cf, org_cf)
      mapping = {}
      ticket_cf.each { |cf| mapping[cf[:column_name]] = "custom_field_#{cf[:zendesk_id]}" }
      (user_cf + org_cf).each do |cf|
        next unless cf[:zendesk_key]

        mapping[cf[:column_name]] ||= cf[:zendesk_key]
      end
      mapping
    end
  end
end
