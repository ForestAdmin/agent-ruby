module ForestAdminDatasourceZendesk
  class Datasource < ForestAdminDatasourceToolkit::Datasource
    attr_reader :client, :configuration, :custom_field_mapping,
                :default_ticket_subject, :default_ticket_message, :requester_email_default,
                :close_ticket_statuses

    # Optional kwargs:
    #
    # CreateTicketWithNotification smart action (auto-registered on ZendeskUser):
    #   * `default_ticket_subject` / `default_ticket_message` are strings that
    #     support `{{record.<field>}}` tokens, interpolated against the
    #     selected record when the form opens. `default_ticket_message` is
    #     rendered in a RichText widget and shipped to Zendesk as `html_body`.
    #   * `requester_email_default` is a literal email String used as the
    #     static default for the "Requester email" form field. When unset,
    #     ZendeskUser falls back to reading `record['email']` off the
    #     selected user. (When attaching the action to a non-ZendeskUser
    #     collection via `register_on(...)`, this kwarg also accepts a Proc
    #     `record -> email_string` for callers that need to compute it.)
    #
    # CloseTicket smart actions (registered on ZendeskTicket):
    #   * `close_ticket_statuses` is the opt-in list of close actions to
    #     expose, picked from `%w[solved closed]`. Defaults to `[]` — no
    #     close actions are registered unless explicitly listed. Each listed
    #     status registers both a Single and a Bulk variant.
    #
    # All-kwargs constructor — the ParameterLists cop counts each kwarg toward
    # its 5-param limit, which doesn't really apply to named arguments.
    def initialize(subdomain:, username:, token:, # rubocop:disable Metrics/ParameterLists
                   default_ticket_subject: nil, default_ticket_message: nil,
                   requester_email_default: nil, close_ticket_statuses: [])
      super()
      @configuration = Configuration.new(subdomain: subdomain, username: username, token: token)
      @client = Client.new(@configuration)
      @custom_field_mapping = {}
      @default_ticket_subject = default_ticket_subject
      @default_ticket_message = default_ticket_message
      @requester_email_default = requester_email_default
      @close_ticket_statuses = Array(close_ticket_statuses).map(&:to_s)

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
