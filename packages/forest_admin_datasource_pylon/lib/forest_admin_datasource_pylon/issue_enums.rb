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

    # The one state every organization has: the others Pylon ships, and the
    # custom ones defined on top of them, are named by the option that writes
    # them rather than listed here.
    CLOSED_STATE = 'closed'.freeze
  end
end
