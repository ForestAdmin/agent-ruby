require 'forest_admin_agent'
require 'rack/cors'

module Rack
  class Cors
    class Resource
      def to_preflight_headers(env)
        h = to_headers(env)
        if env['HTTP_ACCESS_CONTROL_REQUEST_PRIVATE_NETWORK'] == 'true'
          h['Access-Control-Allow-Private-Network'] = 'true'
        end
        if env[HTTP_ACCESS_CONTROL_REQUEST_HEADERS]
          h['Access-Control-Allow-Headers'] = env[HTTP_ACCESS_CONTROL_REQUEST_HEADERS]
        end
        h
      end
    end
  end
end

module ForestAdminRails
  class Engine < ::Rails::Engine
    isolate_namespace ForestAdminRails

    config.after_initialize do
      agent_factory = ForestAdminAgent::Builder::AgentFactory.instance
      agent_factory.setup(ForestAdminRails.config)
      load_configuration
      load_cors
    end

    def load_configuration
      return unless File.exist?(Rails.root.join('lib', 'forest_admin_rails', 'create_agent.rb'))

      # force eager loading models
      Rails.application.eager_load!

      # setup agent
      Dir[Rails.root.join('lib', 'forest_admin_rails', '**', '*.rb')].each { |file| require file }

      ForestAdminRails::CreateAgent.setup!

      sse = ForestAdminAgent::Services::SSECacheInvalidation
      sse.run if ForestAdminRails.config[:instant_cache_refresh]
    end

    def load_cors
      config.middleware.insert_before 0, Rack::Cors do
        allow do
          hostnames = [/\A.*\.forestadmin\.com\z/]
          hostnames += ENV['CORS_ORIGINS'].split(',') if ENV['CORS_ORIGINS']

          origins hostnames
          resource '*', headers: :any, methods: :any, credentials: true, max_age: 86_400
        end
      end
    end
  end
end
