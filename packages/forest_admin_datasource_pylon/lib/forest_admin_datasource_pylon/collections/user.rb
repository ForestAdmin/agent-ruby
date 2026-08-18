module ForestAdminDatasourcePylon
  module Collections
    class User < FetchAllCollection
      NATIVE_FIELDS = %w[id name email emails avatar_url status role_id is_deactivated].freeze

      def initialize(datasource)
        super(datasource, 'PylonUser')
      end

      protected

      # `include_deactivated` is left at the client default of true on purpose:
      # a deactivated agent stays the assignee and the author of the issues they
      # handled, and a record the rest of the panel points at has to stay
      # readable. `is_deactivated` is exposed as a column so an operator can
      # filter them out when they want to.
      def fetch_all
        datasource.client.fetch_users
      end

      # `role` is flattened to its name only: its id is already carried by
      # `role_id`, and the name is what an operator recognises. Its slug is left
      # out — Pylon derives it from the name.
      def serialize(user)
        attrs = user.is_a?(Hash) ? user : {}
        role = attrs['role']

        NATIVE_FIELDS.to_h { |field| [field, attrs[field]] }
                     .merge('role_name' => role.is_a?(Hash) ? role['name'] : nil)
      end

      private

      # `/issues/search` filters `assignee_id` server-side, so the issues of an
      # agent are listed by one request.
      #
      # The teams of a user are left out: Pylon nests the members inside a team
      # and exposes no team id on a user, so that side is a ManyToMany with no
      # key column to build it on.
      def define_relations
        add_field('assigned_issues', OneToManySchema.new(foreign_collection: 'PylonIssue',
                                                         origin_key: 'assignee_id', origin_key_target: 'id'))
      end

      def define_schema
        add_column('id', 'String', is_primary_key: true)
        add_column('name', 'String')
        add_column('email', 'String')
        # The other addresses of the same agent: a list, so it is neither
        # filterable nor sortable. `email` carries the primary one.
        add_column('emails', 'Json')
        add_column('avatar_url', 'String')
        # Left as String rather than Enum: Pylon documents active / away /
        # out_of_office on the update endpoint, but does not promise the read
        # side is limited to them.
        add_column('status', 'String')
        add_column('role_id', 'String')
        add_column('role_name', 'String')
        add_column('is_deactivated', 'Boolean')
      end
    end
  end
end
