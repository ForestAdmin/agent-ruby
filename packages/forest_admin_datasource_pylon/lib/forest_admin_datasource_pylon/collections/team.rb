module ForestAdminDatasourcePylon
  module Collections
    class Team < FetchAllCollection
      def initialize(datasource)
        super(datasource, 'PylonTeam')
      end

      protected

      # `delete_record` is left alone: Pylon exposes no DELETE on a team, and
      # the default hook refuses the verb with a message rather than a 500.
      def create_record(payload) = datasource.client.create_team(payload)
      def update_record(id, payload) = datasource.client.update_team(id, payload)

      def fetch_all
        datasource.client.fetch_teams
      end

      # `users` is flattened to the ids of the members: the emails Pylon nests
      # there belong to PylonUser, which is where they stay up to date.
      def serialize(team)
        attrs = team.is_a?(Hash) ? team : {}

        { 'id' => attrs['id'], 'name' => attrs['name'],
          'user_ids' => Array(attrs['users']).filter_map { |user| user['id'] if user.is_a?(Hash) } }
      end

      private

      # `/issues/search` filters `team_id` server-side, so the issues assigned to
      # a team are listed by one request. `user_ids` gets no relation: Pylon
      # nests the members here rather than pointing at the team from a user, so
      # the membership is a ManyToMany with no join collection to declare it on.
      def define_relations
        add_field('issues', OneToManySchema.new(foreign_collection: 'PylonIssue',
                                                origin_key: 'team_id', origin_key_target: 'id'))
      end

      def define_schema
        add_column('id', 'String', is_primary_key: true)
        add_column('name', 'String', writable: true)
        # A list, so neither filterable nor sortable, and no relation either:
        # see `define_relations` above. Writable: `POST /teams` and
        # `PATCH /teams/{id}` take the members as this very list of ids, and the
        # one sent replaces the membership whole.
        add_column('user_ids', 'Json', writable: true)
      end
    end
  end
end
