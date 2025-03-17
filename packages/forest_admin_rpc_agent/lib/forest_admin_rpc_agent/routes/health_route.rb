# module ForestAdminRpcAgent
#   module Routes
#     class HealthRoute < BaseRoute
#       def self.registered(app)
#         app.get '/forest_admin_rpc/health' do
#           content_type :json
#           status 200
#           { status: 'ok', message: 'Forest Admin RPC Agent is running' }.to_json
#         end
#       end
#     end
#   end
# end
module ForestAdminRpcAgent
  module Routes
    class HealthRoute < BaseRoute
      def self.register_sinatra(app)
        app.get '/forest_admin_rpc/health' do
          content_type :json
          status 200
          { status: 'ok', message: 'Forest Admin RPC Agent is running' }.to_json
        end
      end

      def self.register_rails(router)
        router.get '/forest_admin_rpc/health', to: 'rpc#health'
      end
    end
  end
end
