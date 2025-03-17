module ForestAdminRpcAgent
  class Engine < ::Rails::Engine
    isolate_namespace ForestAdminRpcAgent

    config.after_initialize do
      Rails.error.handle(ForestAdminDatasourceToolkit::Exceptions::ForestException) do
        agent = ForestAdminRpcAgent::Agent.instance
        agent.setup(ForestAdminRpcAgent.config)
        ForestAdminRpcAgent::Extensions::ConfigLoader.load_configuration
      end
    end
  end
end
