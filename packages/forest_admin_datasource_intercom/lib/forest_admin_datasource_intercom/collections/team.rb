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
          # Not a column: it is what the names below are read from, and what the
          # membership collection turns into the relation. Intercom types these
          # as numbers here and as strings on the admin itself, so they are
          # stringified for both sides to carry the same id.
          'admin_ids' => Array(attrs['admin_ids']).map { |id| stringify_id(id) },
          'admin_names' => nil }
      end

      # The teammates of the team, by name, and only when a projection asked for
      # them: one read of `/admins` for the whole page, never one per team. A
      # token that cannot read the teammates costs the column and nothing else.
      def enrich(records, rows, projection)
        return unless column_asked?(projection, 'admin_names')

        names = admin_names
        records.each_with_index do |record, index|
          rows[index]['admin_names'] = Array(record['admin_ids']).filter_map { |id| names[id] }
        end
      end

      private

      def admin_names
        client.fetch_all('admins', list_key: 'admins')
              .to_h { |admin| [stringify_id(admin['id']), admin['name']] }
      rescue APIError => e
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] #{name} could not read the teammates of the workspace (HTTP " \
          "#{e.status || "-"}); the names are left empty. The relation to IntercomAdmin is unaffected."
        )
        {}
      end

      def define_schema
        add_column('id', 'String', is_primary_key: true)
        add_column('name', 'String')
        # A list, so neither filterable nor sortable -- as the array of ids it
        # replaces was. It reads the team without a join; the relation below is
        # what navigates it, and filtering happens on the Admins collection.
        add_column('admin_names', 'Json')
        add_many_to_many('admins', foreign_collection: 'IntercomAdmin',
                                   through_collection: 'IntercomTeamMembership',
                                   origin_key: 'team_id', foreign_key: 'admin_id')
      end
    end
  end
end
