module ForestAdminDatasourceIntercom
  module Collections
    # The membership of the inbox teams: one record per team-and-teammate pair.
    #
    # It exists because Intercom's does not. The workspace carries the membership
    # on the team (`admin_ids`) and on the teammate (`team_ids`) both, and offers
    # no resource for the pair -- while a many-to-many needs a collection to
    # travel through, whose two many-to-one relations are what
    # `Utils::Collection.get_through_target` looks for. Declared here, Teams and
    # Admins navigate to each other in both directions; left undeclared, both
    # sides read as an array of ids.
    #
    # Read from `/teams`, keeping only the teammates `/admins` still answers:
    # one who left is named by `admin_ids` until Intercom drops the pair, and a
    # pair whose teammate is gone would be counted by a related list that
    # cannot show it. Both reads share the reference cache.
    # Read-only, like the relations it carries: Intercom exposes no endpoint that
    # writes a membership, and an editable relation would offer an association
    # that could only fail.
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
