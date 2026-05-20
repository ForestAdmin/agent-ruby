require 'cgi'
require 'json'
require 'jsonapi-serializers'

module ForestAdminRpcAgent
  module Routes
    class ActionExecute < BaseRoute
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminAgent::Utils
      include ForestAdminAgent::Routes::QueryHandler

      def initialize
        super('rpc/:collection_name/action-execute', 'post', 'rpc_action_execute')
      end

      def handle_request(args)
        datasource = ForestAdminRpcAgent::Facades::Container.datasource
        collection = get_collection_safe(datasource, args[:params]['collection_name'])
        filter = FilterFactory.from_plain_object(args[:params]['filter'])
        data = args[:params]['data']
        action = args[:params]['action']

        result = collection.execute(args[:caller], action, data, filter)

        return build_file_response(result) if file_result?(result)

        result
      end

      private

      def file_result?(result)
        result.is_a?(Hash) && result[:type] == 'File'
      end

      def build_file_response(result)
        encoded_name = CGI.escape(result[:name].to_s)
        headers = {
          'Content-Type' => result[:mime_type],
          'Content-Disposition' => %(attachment; filename="#{encoded_name}"),
          'X-Forest-Action-Type' => 'File',
          'X-Forest-Action-File-Name' => encoded_name
        }
        headers['X-Forest-Action-Response-Headers'] = result[:response_headers].to_json if result[:response_headers]

        { status: 200, headers: headers, content: result[:stream] }
      end
    end
  end
end
