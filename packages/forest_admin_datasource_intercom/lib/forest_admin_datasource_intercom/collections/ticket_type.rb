module ForestAdminDatasourceIntercom
  module Collections
    # The ticket types the workspace defines. They are what makes a ticket's type
    # readable, and they are also where the ticket attributes are declared --
    # which is what the ticket collection reads them for.
    class TicketType < FetchAllCollection
      def initialize(datasource)
        super(datasource, 'IntercomTicketType')
      end

      protected

      def fetch_all
        client.fetch_all('ticket_types')
      end

      # `ticket_type_attributes` is deliberately left out: it is a nested list of
      # attribute definitions, useful to the ticket collection and meaningless as
      # a column. An attribute of the same name carries a different id from one
      # type to the next (measured), which is exactly why the ticket collection
      # has to read the definitions rather than assume them.
      def serialize(ticket_type)
        attrs = ticket_type.is_a?(Hash) ? ticket_type : {}

        { 'id' => stringify_id(attrs['id']),
          'name' => attrs['name'],
          'description' => attrs['description'],
          'category' => attrs['category'],
          'icon' => attrs['icon'],
          'archived' => attrs['archived'] }
      end

      private

      def define_schema
        add_column('id', 'String', is_primary_key: true)
        add_column('name', 'String')
        add_column('description', 'String')
        # `request` / `task` / `tracker` on the wire, not the labels the Intercom
        # interface shows -- the same mismatch the ticket filter has to respect.
        add_column('category', 'String')
        add_column('icon', 'String')
        add_column('archived', 'Boolean')
      end
    end
  end
end
