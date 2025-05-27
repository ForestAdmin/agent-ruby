module ForestAdminRpcAgent
  module Extensions
    module ConfigLoader
      def self.load_configuration
        config_file = File.join(Dir.pwd, 'app', 'lib', 'forest_admin_rpc_agent', 'create_rpc_agent.rb')
        return unless File.exist?(config_file)

        ForestAdminRpcAgent::CreateRpcAgent.setup!
      end
    end
  end
end
