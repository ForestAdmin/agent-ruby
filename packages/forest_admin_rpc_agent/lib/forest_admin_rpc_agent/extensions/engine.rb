module ForestAdminRpcAgent
  module Extensions
    class Engine < ::Rails::Engine
      isolate_namespace ForestAdminRpcAgent

      initializer 'forest_admin_rpc_agent.setup' do |app|
        app.config.after_initialize do
          agent = ForestAdminRpcAgent::Agent.instance
          agent.setup(ForestAdminRpcAgent.config)
          ForestAdminRpcAgent::Extensions::ConfigLoader.load_configuration
        end
      end
    end
  end
end
