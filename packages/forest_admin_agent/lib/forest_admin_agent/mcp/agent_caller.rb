require 'faraday'
require 'json'

module ForestAdminAgent
  module Mcp
    class AgentCaller
      def initialize(auth_info)
        @token = auth_info[:token]
        @forest_server_token = auth_info.dig(:extra, :forest_server_token)
        @api_endpoint = auth_info.dig(:extra, :environment_api_endpoint)
      end

      def collection(name)
        CollectionClient.new(name, @forest_server_token, @api_endpoint)
      end

      class CollectionClient
        def initialize(name, token, api_endpoint)
          @name = name
          @token = token
          @api_endpoint = api_endpoint
        end

        def list(params = {})
          payload = build_list_payload(params)

          response = http_client.post("/forest/rpc/#{@name}/list", payload.to_json)

          handle_response(response)
        end

        private

        def build_list_payload(params)
          payload = {}

          payload[:filters] = params[:filters] if params[:filters]

          payload[:search] = params[:search] if params[:search]

          if params[:sort]
            payload[:sort] = [
              {
                field: params[:sort][:field],
                ascending: params[:sort][:ascending]
              }
            ]
          end

          payload
        end

        def handle_response(response)
          unless response.success?
            error_body = parse_error_body(response)
            raise ForestAdminAgent::Http::Exceptions::BadRequestError, error_body
          end

          JSON.parse(response.body)
        end

        def parse_error_body(response)
          body = response.body

          return body if body.is_a?(String) && !body.empty?

          return body['error'] || body['message'] || body.to_json if body.is_a?(Hash)

          "Request failed with status #{response.status}"
        end

        def http_client
          @http_client ||= Faraday.new(@api_endpoint) do |conn|
            conn.headers['Content-Type'] = 'application/json'
            conn.headers['Authorization'] = "Bearer #{@token}"
            conn.ssl.verify = !ForestAdminAgent::Facades::Container.cache(:debug)
          end
        end
      end
    end
  end
end
