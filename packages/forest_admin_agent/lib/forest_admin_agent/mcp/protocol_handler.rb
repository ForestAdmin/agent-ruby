module ForestAdminAgent
  module Mcp
    class ProtocolHandler
      JSONRPC_VERSION = '2.0'.freeze

      def initialize(forest_server_url = nil)
        @forest_server_url = forest_server_url || Facades::Container.cache(:forest_server_url)
        @collection_names = []
        fetch_collection_names
      end

      def handle_request(request, auth_info)
        method = request['method']
        id = request['id']
        params = request['params'] || {}

        result = case method
                 when 'initialize'
                   handle_initialize(params)
                 when 'tools/list'
                   handle_tools_list
                 when 'tools/call'
                   handle_tools_call(params, auth_info)
                 when 'ping'
                   handle_ping
                 else
                   return jsonrpc_error(id, -32_601, "Method not found: #{method}")
                 end

        jsonrpc_response(id, result)
      rescue StandardError => e
        jsonrpc_error(id, -32_603, e.message)
      end

      private

      def fetch_collection_names
        @collection_names = begin
          schema = SchemaFetcher.fetch_forest_schema(@forest_server_url)
          SchemaFetcher.get_collection_names(schema)
        rescue StandardError => e
          Facades::Container.logger.log(
            'Warn',
            "[MCP] Failed to fetch schema, collection names will not be available: #{e.message}"
          )
          []
        end
      end

      def handle_initialize(_params)
        {
          protocolVersion: '2024-11-05',
          capabilities: {
            tools: {}
          },
          serverInfo: {
            name: '@forestadmin/mcp-server',
            version: '0.1.0'
          }
        }
      end

      def handle_tools_list
        {
          tools: available_tools
        }
      end

      def handle_tools_call(params, auth_info)
        tool_name = params['name']
        arguments = params['arguments'] || {}

        case tool_name
        when 'list'
          Tools::ListTool.execute(arguments, auth_info, @forest_server_url)
        else
          raise "Unknown tool: #{tool_name}"
        end
      end

      def handle_ping
        {}
      end

      def available_tools
        [
          Tools::ListTool.definition(@collection_names)
        ]
      end

      def jsonrpc_response(id, result)
        {
          jsonrpc: JSONRPC_VERSION,
          id: id,
          result: result
        }
      end

      def jsonrpc_error(id, code, message)
        {
          jsonrpc: JSONRPC_VERSION,
          id: id,
          error: {
            code: code,
            message: message
          }
        }
      end
    end
  end
end
