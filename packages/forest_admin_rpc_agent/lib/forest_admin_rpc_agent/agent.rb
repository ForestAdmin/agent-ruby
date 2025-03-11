require 'grpc'
require_relative 'proto/rpc_pb'
require_relative 'proto/rpc_services_pb'

module ForestAdminRpcAgent
  class Agent
    def initialize(host: 'localhost', port: 4567)
      @stub = ForestAdminRpcAgent::Rpc::Stub.new("#{host}:#{port}", :this_channel_is_insecure)
    end

    def list_users
      request = ForestAdminRpcAgent::Empty.new
      response = @stub.list_users(request)
      response.users
    rescue GRPC::BadStatus => e
      puts "RPC error: #{e.message}"
      []
    end
  end
end
