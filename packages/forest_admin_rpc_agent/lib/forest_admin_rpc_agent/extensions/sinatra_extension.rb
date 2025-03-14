require 'sinatra/base'

module ForestAdminRpcAgent
  module Extensions
    module SinatraExtension
      def self.registered(app)
        app.before do
          agent = ForestAdminRpcAgent::Agent.instance
          agent.setup(ForestAdminRpcAgent.config)
          ForestAdminRpcAgent::Extensions::ConfigLoader.load_configuration
        end

        app.get '/forest_admin_rpc' do
          'ForestAdmin RPC Agent is running!'
        end

        # TODO: OTHERS ROUTES
      end
    end
  end
end

Sinatra::Base.register ForestAdminRpcAgent::Extensions::SinatraExtension
