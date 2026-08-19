module ForestAdminDatasourcePylon
  # The closed sets `POST /issues` and `PATCH /issues/{id}` document, shared by
  # the plugins building forms over them.
  module IssueEnums
    # Accepted on a create, and absent from every read: Pylon never returns the
    # priority of an issue, which is why no column carries it.
    PRIORITY = %w[urgent high medium low].freeze

    # Where the first message of a created issue is delivered. `internal` is the
    # absence of a delivery, and travels as no `destination_metadata` at all.
    DESTINATION = %w[email slack in_app_chat customer_portal sms whatsapp internal].freeze

    INTERNAL_DESTINATION = 'internal'.freeze

    # The states Pylon ships. An organization defines its own on top of them, so
    # this list is what a form offers, never what a write is checked against.
    STANDARD_STATES = %w[new waiting_on_you waiting_on_customer on_hold closed].freeze

    CLOSED_STATE = 'closed'.freeze
  end
end
