module ForestAdminSinatra
  module Extensions
    module ConfigLoader
      def self.load_configuration
        config_file = File.join(Dir.pwd, 'app', 'lib', 'forest_admin_sinatra', 'create_agent.rb')
        return unless File.exist?(config_file)

        ForestAdminSinatra::CreateAgent.setup!
      end
    end
  end
end
