module ForestadminRails
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)
      argument :env_secret, type: :string, required: true, desc: 'required', banner: 'env_secret'

      def install
        @auth_secret = SecureRandom.hex(20)
        @env_secret = env_secret
        template 'config.rb', 'config/initializers/forestadmin_rails.rb'

        # mount ForestRails::Engine, at: '/forest'
      end
    end
  end
end
