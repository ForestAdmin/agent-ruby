require 'thor'
require 'fileutils'

module ForestAdminRpcAgent
  module Thor
    class Install < ::Thor
      include ::Thor::Actions
      # Run the command:
      # for a rails app : forest_admin_rpc_agent install AUTH_SECRET_FROM_YOUR_FOREST_APP
      # for a sinatra app : forest_admin_rpc_agent install AUTH_SECRET_FROM_YOUR_FOREST_APP --app_file=app.rb

      desc 'install AUTH_SECRET_FROM_YOUR_FOREST_APP',
           'Install ForestAdmin RPC Agent by generating necessary configuration and files'
      method_option :app_file, type: :string, required: false, desc: 'Main file of the Sinatra application (ex: app.rb)'

      RAILS_CONFIG_PATH = 'config/initializers/forest_admin_rpc_agent.rb'.freeze
      RAILS_AGENT_PATH  = 'app/lib/forest_admin_rpc_agent/create_rpc_agent.rb'.freeze

      SINATRA_CONFIG_PATH = 'config/forest_admin_rpc_agent.rb'.freeze
      SINATRA_AGENT_PATH  = 'config/create_rpc_agent.rb'.freeze

      def install(auth_secret)
        if rails_app?
          say_status('info', 'Rails framework detected ✅', :green)
          setup_rails(auth_secret)
        elsif sinatra_app?
          if options[:app_file].nil?
            say_status('error', 'You must specify the main file of the Sinatra application with --app_file', :red)
            raise ::Thor::Error, 'You must specify the main file of the Sinatra application with --app_file'
          end
          say_status('info', 'Sinatra framework detected ✅', :green)
          setup_sinatra(auth_secret)
        else
          say_status('error', 'Unsupported framework', :red)
          raise ::Thor::Error, 'Unsupported framework, only Rails and Sinatra are supported with ForestAdmin RPC Agent'
        end
      end

      private

      def setup_rails(auth_secret)
        require 'rails/generators'
        require 'rails/generators/actions'

        create_config_files(auth_secret, RAILS_CONFIG_PATH, RAILS_AGENT_PATH)

        klass = Class.new(Rails::Generators::Base) do
          include Rails::Generators::Actions
        end
        klass.new.route("mount ForestAdminRpcAgent::Engine => '/forest_admin_rpc'")

        say_status('success', 'ForestAdmin RPC Agent installed on Rails ✅', :green)
      end

      def setup_sinatra(auth_secret)
        create_config_files(auth_secret, SINATRA_CONFIG_PATH, SINATRA_AGENT_PATH)

        app_file_content = File.read(options[:app_file])
        if app_file_content.include?("require 'sinatra'")
          insert_into_file options[:app_file], <<~RUBY, after: "require 'sinatra'\n"
            require_relative 'config/forest_admin_rpc_agent'
            require 'forest_admin_rpc_agent/extensions/sinatra_extension'
          RUBY

          say_status('success', 'ForestAdmin RPC Agent installed on Sinatra ✅', :green)
        else
          say_status('error', "Could not find `require 'sinatra'` in #{options[:app_file]}", :red)
          raise ::Thor::Error, "Please add `require 'sinatra'` in #{options[:app_file]} before running this command."
        end
      end

      def create_config_files(auth_secret, config_path, agent_path)
        # Create necessary directories
        FileUtils.mkdir_p(File.dirname(config_path))
        FileUtils.mkdir_p(File.dirname(agent_path))

        # Create configuration file
        create_file config_path, <<~RUBY
          ForestAdminRpcAgent.configure do |config|
            config.auth_secret = '#{auth_secret}'
          end
        RUBY

        # Create agent setup file
        create_file agent_path, <<~RUBY
          # This file contains code to create and configure your Forest Admin agent
          # You can customize this file according to your needs

          module ForestAdminRpcAgent
            class CreateRpcAgent
              def self.setup!
                # Initialize your agent here
              end
            end
          end
        RUBY
      end

      def rails_app?
        return true if Object.const_defined?(:Rails) && Rails.respond_to?(:root)

        File.exist?('config/application.rb') && Dir.exist?('app/controllers')
      end

      def sinatra_app?
        # 1. Check if Sinatra is already loaded in memory
        return true if defined?(Sinatra::Base)

        # 2. Check Gemfile.lock
        return true if File.exist?('Gemfile.lock') && File.read('Gemfile.lock').include?('sinatra')

        # 3. Check config.ru
        return true if File.exist?('config.ru') && File.read('config.ru') =~ %r{require ['"]sinatra(/base)?['"]}

        # 4. Look for a class that inherits from Sinatra in Ruby files
        Dir.glob('*.rb').any? do |file|
          content = File.read(file)
          content.match?(%r{require ['"](sinatra|sinatra/base)['"]}) &&
            (content.include?('< Sinatra::') || content.include?('Sinatra::Application'))
        end
      end

      class << self
        private

        def exit_on_failure?
          true
        end

        def source_root
          File.dirname(__FILE__)
        end
      end
    end
  end
end
