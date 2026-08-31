module ForestAdminDatasourceIntercom
  module Collections
    # The inbox teams a conversation can be assigned to, rather than a single
    # teammate.
    class Team < FetchAllCollection
      def initialize(datasource)
        super(datasource, 'IntercomTeam')
      end

      protected

      # Like `/admins`, `/teams` uses its own key instead of the `data` envelope.
      def fetch_all
        client.fetch_all('teams', list_key: 'teams')
      end

      def serialize(team)
        attrs = team.is_a?(Hash) ? team : {}

        { 'id' => stringify_id(attrs['id']),
          'name' => attrs['name'],
          'admin_ids' => Array(attrs['admin_ids']).map { |id| stringify_id(id) } }
      end

      private

      def define_schema
        add_column('id', 'String', is_primary_key: true)
        add_column('name', 'String')
        # Intercom types these as numbers here and as strings on the admin
        # itself; they are stringified so both sides carry the same id.
        add_column('admin_ids', 'Json')
      end
    end
  end
end
