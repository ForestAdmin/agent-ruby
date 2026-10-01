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
          # Not a column: it is what the names below are read from, and what the
          # membership collection turns into the relation.
          'team_ids' => Array(attrs['team_ids']).map { |id| stringify_id(id) },
          'team_names' => nil }
      end

      # The teams the teammate belongs to, by name, and only when a projection
      # asked for them: one read of `/teams` for the whole page. A token that
      # cannot read them costs the column and nothing else.
      def enrich(records, rows, projection)
        return unless column_asked?(projection, 'team_names')

        names = team_names
        records.each_with_index do |record, index|
          rows[index]['team_names'] = Array(record['team_ids']).filter_map { |id| names[id] }
        end
      end

      private

      def team_names
        client.fetch_all('teams', list_key: 'teams')
              .to_h { |team| [stringify_id(team['id']), team['name']] }
      rescue APIError => e
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] #{name} could not read the teams of the workspace (HTTP " \
          "#{e.status || "-"}); the names are left empty. The relation to IntercomTeam is unaffected."
        )
        {}
      end

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
        # A list, so neither filterable nor sortable -- as the array of ids it
        # replaces was. It reads the teammate without a join; the relation below
        # is what navigates it, through the membership collection that gives the
        # many-to-many the join Intercom does not expose.
        add_column('team_names', 'Json')
        add_many_to_many('teams', foreign_collection: 'IntercomTeam',
                                  through_collection: 'IntercomTeamMembership',
                                  origin_key: 'admin_id', foreign_key: 'team_id')
      end
    end
  end
end
