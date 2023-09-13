require 'forest_admin_agent'

module ForestAdminRails
  class Engine < ::Rails::Engine
    isolate_namespace ForestAdminRails

    config.after_initialize do
      agent_factory = ForestAdminAgent::Builder::AgentFactory.instance
      agent_factory.setup(ForestAdminRails.config)
      load_configuration
    end

    def load_configuration
      return unless File.exist?(Rails.root.join('config', 'forest_admin.rb'))

      require Rails.root.join('config', 'forest_admin.rb')

      ForestAdminAgent::Builder::AgentFactory.instance.build
    end
  end
end
