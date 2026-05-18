module ForestAdminDatasourceZendesk
  # Shared between the Ticket schema and plugins that build ticket forms.
  module TicketEnums
    STATUS   = %w[new open pending hold solved closed].freeze
    PRIORITY = %w[low normal high urgent].freeze
    TYPE     = %w[problem incident question task].freeze
  end
end
