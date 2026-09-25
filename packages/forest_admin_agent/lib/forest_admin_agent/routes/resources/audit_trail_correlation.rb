module ForestAdminAgent
  module Routes
    module Resources
      # Correlation-scoped record-history routes, mirroring the Node agent's
      # `/_audit-trail/correlation/:key` and `/_audit-trail/correlations`. Registered only when
      # `config.audit_trail[:database]` is set. All three routes are scoped to a single record through the
      # `collection`/`recordId` query (GET) or body (POST) params and share the per-record auth.
      class AuditTrailCorrelation < AbstractAuthenticatedRoute
        include AuditTrailRoute

        def setup_routes
          return self unless store

          add_route(
            'forest_audit_trail_correlation',
            'get',
            '/_audit-trail/correlation/:correlation_key',
            ->(args) { handle_history(args) }
          )
          # GET carries the keys in `correlationKeys`; POST accepts a body list to dodge URL limits.
          add_route(
            'forest_audit_trail_correlations',
            'get',
            '/_audit-trail/correlations',
            ->(args) { handle_batch(args) }
          )
          add_route(
            'forest_audit_trail_correlations_batch',
            'post',
            '/_audit-trail/correlations',
            ->(args) { handle_batch(args) }
          )

          self
        end

        def handle_history(args = {})
          context, collection, record_id, scope = assert_scope(args)

          history = store.list_by_correlation(
            collection: collection.name,
            record_id: record_id,
            correlation_key: args[:params]['correlation_key']
          )
          data = withhold_gone_record(history, context, collection, record_id, scope)

          { name: collection.name, content: { data: data.map { |record| serialize_record(record) } } }
        end

        def handle_batch(args = {})
          context, collection, record_id, scope = assert_scope(args)
          correlation_keys = parse_correlation_keys(args)

          history = if correlation_keys.empty?
                      []
                    else
                      store.list_by_correlations(
                        collection: collection.name,
                        record_id: record_id,
                        correlation_keys: correlation_keys
                      )
                    end
          data = withhold_gone_record(history, context, collection, record_id, scope)

          { name: collection.name, content: { data: data.map { |record| serialize_record(record) } } }
        end

        private

        # These routes serve the same rows as the per-record history route, so a gone record's captured values
        # are tested against the caller's scope here too — otherwise what that route withholds comes back
        # through a correlation lookup. Asked again rather than reused from the check that authorized the
        # request, which ran before these rows were read.
        def withhold_gone_record(history, context, collection, record_id, scope)
          # An empty answer has nothing to withhold, so it does not earn a second read of the record.
          return history if history.empty?

          scope ||= scope_if_gone_since(context, collection, record_id)

          withhold_out_of_scope_values(history, Withholding.new(collection, scope, context.caller.timezone))
        end

        def assert_scope(args)
          context = build(args)
          name = args.dig(:params, 'collection').to_s
          record_id = args.dig(:params, 'recordId').to_s

          raise Http::Exceptions::ValidationError, 'Missing collection' if name.empty?
          raise Http::Exceptions::ValidationError, 'Missing recordId' if record_id.empty?

          collection = get_collection(context, name)
          context.permissions.can?(:read, collection)

          [context, collection, record_id, assert_record_in_scope(context, collection, record_id)]
        end

        def get_collection(context, name)
          context.datasource.get_collection(name)
        rescue ForestAdminDatasourceToolkit::Exceptions::ForestException => e
          raise Http::Exceptions::NotFoundError, e.message if e.message.include?('not found')

          raise
        end

        # Body array (POST) takes precedence, otherwise the comma-separated query param (GET).
        def parse_correlation_keys(args)
          raw = args.dig(:params, 'correlationKeys')
          keys = raw.is_a?(Array) ? raw : raw.to_s.split(',')

          keys.map { |key| key.to_s.strip }.reject(&:empty?)
        end
      end
    end
  end
end
