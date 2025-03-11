require 'grpc'
require_relative 'proto/rpc_services_pb'

class TempRpcServer < ForestAdminRpcAgent::Rpc::Service
  def list_users(_empty, _call)
    users = [
      ForestAdminRpcAgent::User.new(id: '1', email: 'rick@sanchez.com', first_name: 'Rick', last_name: 'Sanchez'),
      ForestAdminRpcAgent::User.new(id: '2', email: 'morty@smith.com', first_name: 'Morty', last_name: 'Smith'),
      ForestAdminRpcAgent::User.new(id: '3', email: 'summer@smith.com', first_name: 'Summer', last_name: 'Smith'),
      ForestAdminRpcAgent::User.new(id: '4', email: 'beth@smith.com', first_name: 'Beth', last_name: 'Smith'),
      ForestAdminRpcAgent::User.new(id: '5', email: 'jerry@smith.com', first_name: 'Jerry', last_name: 'Smith')
    ]

    ForestAdminRpcAgent::UserList.new(users: users)
  end
end

def main
  address = 'localhost:50051'
  server = GRPC::RpcServer.new
  server.add_http2_port(address, :this_port_is_insecure)
  server.handle(TempRpcServer.new)

  puts "✅ gRPC Server running on #{address}"
  server.run_till_terminated
end

main if __FILE__ == $PROGRAM_NAME
