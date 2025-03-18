module ForestAdminRpcAgent
  class Engine < ::Rails::Engine
    isolate_namespace ForestAdminRpcAgent

    config.after_initialize do
      Rails.error.handle(ForestAdminDatasourceToolkit::Exceptions::ForestException) do
        agent = ForestAdminRpcAgent::Agent.instance
        agent.setup(ForestAdminRpcAgent.config)

        # force eager loading models
        Rails.application.eager_load!

        ForestAdminRpcAgent::Extensions::ConfigLoader.load_configuration
      end
    end
  end
end
