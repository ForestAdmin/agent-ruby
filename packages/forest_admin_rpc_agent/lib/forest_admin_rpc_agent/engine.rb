module ForestAdminRpcAgent
  class Engine < ::Rails::Engine
    isolate_namespace ForestAdminRpcAgent

    initializer 'forest_admin_rpc_agent.add_autoload_paths', before: :set_autoload_paths do |app|
      lib_path = Rails.root.join('lib')
      app.config.autoload_paths << lib_path unless app.config.autoload_paths.frozen?
    end

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
