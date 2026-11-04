module ForestAdminDatasourceIntercom
  module Collections
    # The ticket states of the workspace. A ticket carries its state as an id, so
    # without this collection a support queue reads as a column of numbers.
    class TicketState < FetchAllCollection
      def initialize(datasource)
        super(datasource, 'IntercomTicketState')
      end

      protected

      def fetch_all
        client.fetch_all('ticket_states')
      end

      # Two labels rather than one: `internal_label` is what the support team
      # sees, `external_label` what the customer is shown. An operator reading a
      # queue needs the first, and needs to know what the second says.
      def serialize(ticket_state)
        attrs = ticket_state.is_a?(Hash) ? ticket_state : {}

        { 'id' => stringify_id(attrs['id']),
          'category' => attrs['category'],
          'internal_label' => attrs['internal_label'],
          'external_label' => attrs['external_label'],
          'archived' => attrs['archived'] }
      end

      private

      def define_schema
        add_column('id', 'String', is_primary_key: true)
        add_column('category', 'String')
        add_column('internal_label', 'String')
        add_column('external_label', 'String')
        add_column('archived', 'Boolean')
      end
    end
  end
end
