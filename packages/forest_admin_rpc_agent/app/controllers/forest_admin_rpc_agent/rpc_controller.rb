module ForestAdminRpcAgent
  class RpcController < ApplicationController
    before_action :authenticate_request

    def health
      render json: { status: 'ok', message: 'Forest Admin RPC Agent is running' }, status: :ok
    end

    def process_request
      request_body = request.body.read
      response = ForestAdminRpcAgent::Agent.instance.process_request(request_body)
      render json: response
    end

    private

    def authenticate_request
      auth_middleware = ForestAdminRpcAgent::Middleware::Authentication.new(nil)
      return if auth_middleware.valid_request?(request)

      render json: { error: 'Unauthorized' }, status: :unauthorized
    end
  end
end
