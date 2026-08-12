module ForestAdminAgent
  # The audit trail is inert unless `config.audit_trail[:database]` was set: the agent factory builds
  # the store during setup and stores it in the config, and everything (capture layers and routes)
  # resolves it from here.
  module AuditTrail
    def self.options
      config = Facades::Container.config_from_cache

      (config && config[:audit_trail]) || {}
    end

    def self.store
      options[:store]
    end
  end
end
