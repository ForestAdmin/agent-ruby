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

            # Convert collection name to polymorphic class name (handles renaming)
            polymorphic_class_name = get_polymorphic_class_name_for_collection(collection.datasource, model_name)
            record[schema.foreign_key_type_field] = polymorphic_class_name
          end
        end

        record || {}
      end

      private

      # Helper to convert collection name to polymorphic class name
      # Handles renamed collections by using RenameCollectionDatasourceDecorator if available
      def get_polymorphic_class_name_for_collection(datasource, collection_name)
        # Try to find RenameCollectionDatasourceDecorator in the datasource chain
        rename_ds = find_rename_datasource_decorator(datasource)

        if rename_ds.respond_to?(:get_class_name_for_polymorphic)
          rename_ds.get_class_name_for_polymorphic(collection_name)
        else
          # Fallback: convert collection format to demodulized class name
          collection_name.gsub('__', '::').split('::').last
        end
      end

      # Navigate the datasource chain to find RenameCollectionDatasourceDecorator
      def find_rename_datasource_decorator(_datasource)
        # Access the top-level datasource from Container
        ds = ForestAdminAgent::Facades::Container.datasource

        # Navigate to find CompositeDatasource
        depth = 0
        while ds && ds.class.name != 'ForestAdminDatasourceCustomizer::CompositeDatasource' && depth < 50
          break unless ds.instance_variable_defined?(:@child_datasource)

          ds = ds.instance_variable_get(:@child_datasource)

          depth += 1
        end

        # Search in CompositeDatasource's @datasources array
        if ds&.class&.name == 'ForestAdminDatasourceCustomizer::CompositeDatasource'
          datasources_array = ds.instance_variable_get(:@datasources)
          datasources_array&.each do |datasource_item|
            current = datasource_item
            depth2 = 0
            while current && depth2 < 20
              return current if current.respond_to?(:get_class_name_for_polymorphic)

              break unless current.instance_variable_defined?(:@child_datasource)

              current = current.instance_variable_get(:@child_datasource)

              depth2 += 1
            end
          end
        end

        nil
      end
    end
  end
end
