require 'thor'
require 'securerandom'
require 'fileutils'

module ForestAdminSinatra
  module Thor
    class Install < ::Thor
      include ::Thor::Actions
      # Run the command: forest_admin_sinatra install YOUR_ENV_SECRET --app_file=app.rb

      desc 'install YOUR_ENV_SECRET',
           'Install ForestAdmin Agent by generating necessary configuration and files'
      method_option :app_file, type: :string, required: false, desc: 'Main file of the Sinatra application (ex: app.rb)'

      SINATRA_CONFIG_PATH = 'config/forest_admin_sinatra.rb'.freeze

      def install(env_secret)
        if sinatra_app?
          if options[:app_file].nil?
            say_status('error', 'You must specify the main file of the Sinatra application with --app_file', :red)
            raise ::Thor::Error, 'You must specify the main file of the Sinatra application with --app_file'
          end
          say_status('info', 'Sinatra framework detected ✅', :green)
          setup_sinatra(env_secret)
        else
          say_status('error', 'Unsupported framework', :red)
          raise ::Thor::Error, 'Unsupported framework Sinatra framework not detected'
        end
      end

      private

      def setup_sinatra(env_secret)
        create_config_files(env_secret, SINATRA_CONFIG_PATH)

        app_file_content = File.read(options[:app_file])
        if app_file_content.include?("require 'sinatra'")
          insert_into_file options[:app_file], <<~RUBY, after: "require 'sinatra'\n"
            require_relative 'config/forest_admin_sinatra'
            require 'forest_admin_sinatra/extensions/sinatra_extension'
          RUBY

          say_status('success', 'ForestAdmin Agent installed on Sinatra ✅', :green)
        else
          say_status('error', "Could not find `require 'sinatra'` in #{options[:app_file]}", :red)
          raise ::Thor::Error, "Please add `require 'sinatra'` in #{options[:app_file]} before running this command."
        end
      end

      def create_config_files(env_secret, config_path)
        auth_secret = SecureRandom.hex(20)
        # Create necessary directories
        FileUtils.mkdir_p(File.dirname(config_path))

        # Create configuration file
        create_file config_path, <<~RUBY
          ForestAdminSinatra.configure do |config|
            config.auth_secret = '#{auth_secret}'
            config.env_secret = '#{env_secret}'
          end
        RUBY
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
