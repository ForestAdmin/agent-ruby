module ForestadminRails
  class Engine < ::Rails::Engine
    isolate_namespace ForestadminRails

    config.after_initialize do
      agent_factory = Registry::AgentFactory.instance
      agent_factory.setup(ForestadminRails.config)
      load_configuration
    end

    def load_configuration
      return unless File.exist?(Rails.root.join('config', 'forest_admin.rb'))

      # callback = require Rails.root.join('config', 'forest_admin.rb')
      # callback.call(self)

      Registry::AgentFactory.instance.build
      # loadRoutes should be already loaded by the engine (need to check)
    end
  end
end
