module ForestAdminAgent
  module Routes
    class AbstractAuthenticatedRoute < AbstractRoute
      def build(args = {})
        if args.dig(:headers, 'action_dispatch.remote_ip')
          Facades::Whitelist.check_ip(args[:headers]['action_dispatch.remote_ip'].to_s)
        end

        context = super
        context.caller = Utils::QueryStringParser.parse_caller(args)
        context.permissions = ForestAdminAgent::Services::Permissions.new(context.caller)
        context
      end

      def format_attributes(args, collection)
        record = args[:params][:data][:attributes] || {}

        args[:params][:data][:relationships]&.map do |field, value|
          schema = collection.schema[:fields][field]

          if schema.type == 'ManyToOne'
            record[schema.foreign_key] = value.dig('data', 'id')
          elsif schema.type == 'PolymorphicManyToOne'
            record[schema.foreign_key] = value.dig('data', 'id')
            json_api_type = value.dig('data', 'type')
            # Find matching collection from foreign_collections (handles both singular and plural forms)
            model_name = schema.foreign_collections.find do |coll_name|
              coll = collection.datasource.get_collection(coll_name)
              coll.name == json_api_type || coll.name.pluralize == json_api_type
            rescue ForestAdminDatasourceToolkit::Exceptions::ForestException
              false
            end || json_api_type
            record[schema.foreign_key_type_field] = model_name
          end
        end

        record || {}
      end
    end
  end
end
