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

    extend ActiveSupport::Concern

    initializer 'forest_admin_rails.error_subscribe' do
      Rails.error.subscribe(ForestAdminErrorSubscriber.new)
    end

    config.after_initialize do
      Rails.error.handle(ForestAdminDatasourceToolkit::Exceptions::ForestException) do
        agent_factory = ForestAdminAgent::Builder::AgentFactory.instance
        agent_factory.setup(ForestAdminRails.config)
        load_configuration
        load_cors
      end
    end

    def load_configuration
      return unless running_web_server?
      return unless File.exist?(Rails.root.join('app', 'lib', 'forest_admin_rails', 'create_agent.rb'))

      # force eager loading models
      Rails.application.eager_load!

      begin
        ForestAdminRails::CreateAgent.setup!
      rescue StandardError => e
        logger = ActiveSupport::Logger.new($stdout)
        logger.warn 'An error has occurred during setup of the Forest Admin agent.'
        raise e.message
      end

      sse = ForestAdminAgent::Services::SSECacheInvalidation
      sse.run if ForestAdminRails.config[:instant_cache_refresh]
    end

    def running_web_server?
      return true if defined?(::Rails::Server)

      # check if a web server is running with the given command line arguments
      server_commands = %w[puma unicorn thin passenger rackup]
      return true if server_commands.any? { |cmd| ARGV.any? { |arg| arg.include?(cmd) } }

      # check if running via common server executables
      return true if $PROGRAM_NAME.match?(/puma|unicorn|thin|passenger/)

      false
    end

    def load_cors
      return if ENV['FOREST_CORS_DEACTIVATED']

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
