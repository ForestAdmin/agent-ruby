module ForestAdminAgent
  module Mcp
    module Tools
      class ListTool
        TOOL_NAME = 'list'.freeze

        def self.definition(collection_names = [])
          {
            name: TOOL_NAME,
            title: 'List records from a collection',
            description: 'Retrieve a list of records from the specified collection.',
            inputSchema: build_input_schema(collection_names)
          }
        end

        def self.execute(arguments, auth_info, forest_server_url)
          args = extract_arguments(arguments)
          log_activity(forest_server_url, auth_info, args)
          execute_list(args, auth_info, forest_server_url)
        end

        def self.extract_arguments(arguments)
          {
            collection_name: arguments['collectionName'] || arguments[:collectionName],
            search: arguments['search'] || arguments[:search],
            filters: arguments['filters'] || arguments[:filters],
            sort: arguments['sort'] || arguments[:sort]
          }
        end

        def self.log_activity(forest_server_url, auth_info, args)
          action_type = determine_action_type(args)
          ActivityLogCreator.create(
            forest_server_url,
            auth_info,
            action_type,
            { collection_name: args[:collection_name] }
          )
        end

        def self.determine_action_type(args)
          return 'search' if args[:search]
          return 'filter' if args[:filters]

          'index'
        end

        def self.execute_list(args, auth_info, forest_server_url)
          agent_caller = AgentCaller.new(auth_info)
          params = build_list_params(args)
          result = agent_caller.collection(args[:collection_name]).list(params)

          { content: [{ type: 'text', text: result.to_json }] }
        rescue StandardError => e
          handle_list_error(e, args[:collection_name], forest_server_url)
        end

        def self.build_list_params(args)
          params = {}
          params[:search] = args[:search] if args[:search]
          params[:filters] = { conditionTree: args[:filters] } if args[:filters]
          params[:sort] = args[:sort] if args[:sort]
          params
        end

        def self.handle_list_error(error, collection_name, forest_server_url)
          error_detail = ErrorParser.parse(error)

          raise build_invalid_sort_message(collection_name, forest_server_url) if error_detail&.include?('Invalid sort')

          raise error_detail || error.message
        end

        def self.build_invalid_sort_message(collection_name, forest_server_url)
          schema = SchemaFetcher.fetch_forest_schema(forest_server_url)
          fields = SchemaFetcher.get_fields_of_collection(schema, collection_name)
          sortable_fields = fields.select { |f| f[:is_sortable] }.map { |f| f[:field] }

          'The sort field provided is invalid for this collection. ' \
            "Available fields for the collection #{collection_name} are: #{sortable_fields.join(", ")}."
        end

        def self.build_input_schema(collection_names)
          collection_name_schema = if collection_names.any?
                                     { type: 'string', enum: collection_names }
                                   else
                                     { type: 'string' }
                                   end

          {
            type: 'object',
            properties: {
              collectionName: collection_name_schema,
              search: { type: 'string' },
              filters: FilterSchema.json_schema,
              sort: {
                type: 'object',
                properties: {
                  field: { type: 'string' },
                  ascending: { type: 'boolean' }
                }
              }
            },
            required: ['collectionName']
          }
        end
      end
    end
  end
end
