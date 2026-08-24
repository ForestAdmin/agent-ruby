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

      # Never refused: a write must not 403 because the row it just wrote carries a relation the
      # caller cannot read.
      def redacted_full_projection(context)
        all = ForestAdminDatasourceToolkit::Components::Query::ProjectionFactory.all(context.collection)

        context.permissions.redact_projection(context.collection, all, named_by_caller: false)
      end

      # +with_pks+ runs after the redaction on purpose. It only re-adds keys for relations the
      # redaction kept a path through, and the serializer needs those keys to emit the readable
      # column behind them — dropping them would take the permitted path down with them. A relation
      # the redaction emptied contributes no path, so nothing is re-added for it.
      def redacted_projection_with_pks(context, collection, args)
        requested = Utils::QueryStringParser.parse_requested_projection(collection, args)

        context.permissions.redact_projection(
          collection, requested[:projection], named_by_caller: requested[:named_by_caller]
        ).with_pks(collection)
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
            collection_name = schema.foreign_collections.find do |coll_name|
              coll = collection.datasource.get_collection(coll_name)
              coll.name == json_api_type || coll.name.pluralize == json_api_type
            rescue ForestAdminDatasourceToolkit::Exceptions::ForestException
              false
            end || json_api_type
            record[schema.foreign_key_type_field] = collection_name&.gsub('__', '::')
          end
        end

        record || {}
      end
    end
  end
end
