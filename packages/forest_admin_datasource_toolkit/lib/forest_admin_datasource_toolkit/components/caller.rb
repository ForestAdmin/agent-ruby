module ForestAdminDatasourceToolkit
  module Components
    class Caller
      attr_reader :id, :email, :first_name, :last_name, :tags, :team, :rendering_id, :timezone, :permission_level, :role

      def initialize(
        id:,
        email:,
        first_name:,
        last_name:,
        team:,
        rendering_id:,
        tags:,
        timezone:,
        permission_level:,
        role: nil
      )
        @id = id
        @email = email
        @first_name = first_name
        @last_name = last_name
        @team = team
        @rendering_id = rendering_id
        @tags = tags
        @timezone = timezone
        @permission_level = permission_level
        @role = role
      end
    end
  end
end
