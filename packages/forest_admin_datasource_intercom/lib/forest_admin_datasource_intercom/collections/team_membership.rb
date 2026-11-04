module ForestAdminDatasourceIntercom
  module Collections
    # Synthetic through-collection for the Team <-> Admin many-to-many, which Intercom has no
    # resource for. Pairs whose teammate `/admins` no longer answers are dropped: `admin_ids`
    # keeps naming a teammate who left until Intercom drops the pair.
    class TeamMembership < FetchAllCollection
      def initialize(datasource)
        super(datasource, 'IntercomTeamMembership')
      end

      protected

      def fetch_all
        admin_ids = client.fetch_all('admins', list_key: 'admins')
                          .filter_map { |admin| stringify_id(admin['id']) if admin.is_a?(Hash) }.to_set
        client.fetch_all('teams', list_key: 'teams').flat_map { |team| pairs_of(team, admin_ids) }
      end

      # Keyed by both ids rather than by a counter: a related list is read over
      # two requests, and a key that changed between them would move the rows
      # under the operator.
      def serialize(pair)
        { 'id' => "#{pair["team_id"]}:#{pair["admin_id"]}",
          'team_id' => pair['team_id'],
          'admin_id' => pair['admin_id'] }
      end

      private

      def pairs_of(team, admin_ids)
        return [] unless team.is_a?(Hash)

        team_id = stringify_id(team['id'])
        return [] if team_id.nil?

        Array(team['admin_ids']).filter_map do |admin_id|
          id = stringify_id(admin_id)
          { 'team_id' => team_id, 'admin_id' => id } if admin_ids.include?(id)
        end
      end

      def define_schema
        add_column('id', 'String', is_primary_key: true)
        add_column('team_id', 'String')
        add_column('admin_id', 'String')
        add_many_to_one('team', foreign_collection: 'IntercomTeam', foreign_key: 'team_id')
        add_many_to_one('admin', foreign_collection: 'IntercomAdmin', foreign_key: 'admin_id')
      end
    end
  end
end
