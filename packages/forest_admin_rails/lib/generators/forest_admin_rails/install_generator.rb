module ForestAdminRails
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)
      argument :env_secret, type: :string, required: true, desc: 'required', banner: 'env_secret'

      def install
        @auth_secret = SecureRandom.hex(20)
        @env_secret = env_secret
        template 'initializers/config.rb', 'config/initializers/forest_admin_rails.rb'
        template 'create_agent.rb', 'app/lib/forest_admin_rails/create_agent.rb'
        route 'mount ForestAdminRails::Engine => "#{ForestAdminRails.config[:prefix]}"'
      end
    end
  end
end
