module ForestAdminDatasourceIntercom
  module Collections
    # The teammates of the workspace: who a conversation or a ticket is assigned
    # to. Without this collection an assignee is a raw id on every row.
    class Admin < FetchAllCollection
      def initialize(datasource)
        super(datasource, 'IntercomAdmin')
      end

      protected

      # `/admins` puts its records under `admins`, not under the `data` envelope
      # the paginated listings use.
      def fetch_all
        client.fetch_all('admins', list_key: 'admins')
      end

      def serialize(admin)
        attrs = admin.is_a?(Hash) ? admin : {}

        { 'id' => stringify_id(attrs['id']),
          'name' => attrs['name'],
          'email' => attrs['email'],
          'job_title' => attrs['job_title'],
          'away_mode_enabled' => attrs['away_mode_enabled'],
          'away_mode_reassign' => attrs['away_mode_reassign'],
          'has_inbox_seat' => attrs['has_inbox_seat'],
          'team_ids' => Array(attrs['team_ids']).map { |id| stringify_id(id) } }
      end

      private

      def define_schema
        add_column('id', 'String', is_primary_key: true)
        add_column('name', 'String')
        add_column('email', 'String')
        add_column('job_title', 'String')
        # Whether the teammate is away, and whether their conversations get
        # reassigned while they are: the two an ops lead looks at before
        # assigning anything.
        add_column('away_mode_enabled', 'Boolean')
        add_column('away_mode_reassign', 'Boolean')
        add_column('has_inbox_seat', 'Boolean')
        # A list, so neither filterable nor sortable. It stays a plain column
        # rather than a relation: Intercom carries the membership on the admin
        # and on the team both, so declaring it twice would give the schema two
        # sides of a many-to-many with no join collection to hold it.
        add_column('team_ids', 'Json')
      end
    end
  end
end
