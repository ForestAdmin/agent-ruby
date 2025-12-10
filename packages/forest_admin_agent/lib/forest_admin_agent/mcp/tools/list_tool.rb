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
          collection_name = arguments['collectionName'] || arguments[:collectionName]
          search = arguments['search'] || arguments[:search]
          filters = arguments['filters'] || arguments[:filters]
          sort = arguments['sort'] || arguments[:sort]

          # Determine action type for activity logging
          action_type = if search
                          'search'
                        elsif filters
                          'filter'
                        else
                          'index'
                        end

          # Create activity log
          ActivityLogCreator.create(
            forest_server_url,
            auth_info,
            action_type,
            { collection_name: collection_name }
          )

          # Build RPC client and execute list
          agent_caller = AgentCaller.new(auth_info)

          params = {}
          params[:search] = search if search
          params[:filters] = { conditionTree: filters } if filters
          params[:sort] = sort if sort

          begin
            result = agent_caller.collection(collection_name).list(params)

            {
              content: [
                {
                  type: 'text',
                  text: result.to_json
                }
              ]
            }
          rescue StandardError => e
            error_detail = ErrorParser.parse(e)

            # Provide helpful error message for invalid sort field
            if error_detail&.include?('Invalid sort')
              schema = SchemaFetcher.fetch_forest_schema(forest_server_url)
              fields = SchemaFetcher.get_fields_of_collection(schema, collection_name)
              sortable_fields = fields.select { |f| f[:is_sortable] }.map { |f| f[:field] }

              raise "The sort field provided is invalid for this collection. " \
                    "Available fields for the collection #{collection_name} are: #{sortable_fields.join(', ')}."
            end

            raise error_detail || e.message
          end
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
