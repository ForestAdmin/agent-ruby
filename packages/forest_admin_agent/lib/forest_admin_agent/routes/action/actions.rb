require 'jsonapi-serializers'
require 'active_support/inflector'
require 'jwt'

module ForestAdminAgent
  module Routes
    module Action
      class Actions < AbstractAuthenticatedRoute
        include ForestAdminAgent::Builder
        include ForestAdminAgent::Utils
        include ForestAdminDatasourceToolkit::Components::Query
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
        include ForestAdminDatasourceCustomizer::Decorators::Action

        def initialize(collection, action)
          @action_name = action
          @route_collection = collection
          super()
        end

        def setup_routes
          action_index = @route_collection.schema[:actions].keys.index(@action_name)
          slug = ForestAdminAgent::Utils::Schema::GeneratorAction.get_action_slug(@action_name)
          route_name = "forest_action_#{@route_collection.name}_#{action_index}_#{slug}"
          path = "/_actions/:collection_name/#{action_index}/#{slug}"

          add_route(route_name, 'post', path, proc { |args| handle_request(args) })
          add_route(
            "#{route_name}_load",
            'post',
            "#{path}/hooks/load",
            proc { |args| handle_hook_request(args) }
          )
          add_route(
            "#{route_name}_change",
            'post',
            "#{path}/hooks/change",
            proc { |args| handle_hook_request(args) }
          )
          add_route(
            "#{route_name}_search",
            'post',
            "#{path}/hooks/search",
            proc { |args| handle_hook_request(args) }
          )
          self
        end

        def handle_request(args = {})
          context = build(args)
          args = middleware_custom_action_approval_request_data(args)
          filter_for_caller = get_record_selection(args, context)
          get_record_selection(args, context, include_user_scope: false)

          context.permissions.can_smart_action?(args, context.collection, filter_for_caller)

          raw_data = args.dig(:params, :data, :attributes, :values)

          # As forms are dynamic, we don't have any way to ensure that we're parsing the data correctly
          # better send invalid data to the getForm() customer handler than to the execute() one.
          unsafe_data = Schema::ForestValueConverter.make_form_data_unsafe(raw_data)

          fields = context.collection.get_form(
            context.caller,
            @action_name,
            unsafe_data,
            filter_for_caller,
            { include_hidden_fields: true } # during execute, we need all possible fields
          )

          # Now that we have the field list, we can parse the data again.
          data = Schema::ForestValueConverter.make_form_data(
            context.datasource,
            raw_data,
            fields.reject { |field| field.type == 'Layout' }
          )

          result = execute_and_audit(context, args, data, filter_for_caller)

          { content: ForestAdminAgent::Utils::ActionResult.parse(result) }
        end

        def handle_hook_request(args = {})
          context = build(args)
          forest_fields = args.dig(:params, :data, :attributes, :fields)
          data = (if forest_fields
                    Schema::ForestValueConverter.make_form_data_from_fields(context.datasource,
                                                                            forest_fields)
                  end)
          filter = get_record_selection(args, context)
          search_values = {}
          forest_fields&.each { |field| search_values[field['field']] = field['searchValue'] }

          form = context.collection.get_form(
            context.caller,
            @action_name,
            data,
            filter,
            {
              change_field: args.dig(:params, :data, :attributes, :changed_field),
              search_field: args.dig(:params, :data, :attributes, :search_field),
              search_values: search_values,
              includeHiddenFields: false
            }
          )
          form_elements = Schema::GeneratorAction.extract_fields_and_layout(form)

          {
            content: {
              fields: form_elements[:fields].map do |f|
                Schema::GeneratorAction.build_field_schema(context.datasource, f)
              end,
              layout: Schema::GeneratorAction.build_layout(form_elements[:layout])
            }
          }
        end

        private

        # Recorded as pending before the action runs and confirmed after, so an action that takes the process
        # down with it still leaves evidence that it started. A failed run is worth recording too — "who tried
        # to run this" is usually the interesting part — and an action answering with an Error result failed
        # just as much as one that raised, it simply said so through `result_builder.error`.
        def execute_and_audit(context, _args, data, filter)
          pending = audit_pending(context, data, filter)

          begin
            result = context.collection.execute(context.caller, @action_name, data, filter)
          rescue StandardError
            audit_confirm(pending, failed: true)
            raise
          end

          audit_confirm(pending, result: result, failed: error_result?(result))

          result
        end

        def error_result?(result)
          result.is_a?(Hash) && result[:type] == 'Error'
        end

        # Everything audit-related sits inside the gate, the record selection included: without an audit
        # database none of it runs at all, and a failure refuses the action only under `critical: true` — which
        # is safe here, since the action has not run yet.
        def audit_pending(context, data, filter)
          store = ForestAdminAgent::AuditTrail.store
          return [] unless store

          ForestAdminAgent::AuditTrail.gate do
            action_capture(store).pending(
              caller: context.caller,
              collection: context.collection.name,
              action_name: @action_name,
              form_values: data,
              record_ids: audited_record_ids(context, filter)
            )
          end || []
        end

        def audit_confirm(pending, result: nil, failed: false)
          store = ForestAdminAgent::AuditTrail.store

          action_capture(store).confirm(pending, result: result, failed: failed) if store && pending.any?
        end

        def action_capture(store)
          ForestAdminAgent::AuditTrail::ActionCapture.new(store, ForestAdminAgent::AuditTrail.options[:redact])
        end

        # Packed ids, the form the audit store keys on — read back through the caller's own filter rather than
        # taken from the request. The ids a client sends are a claim: in a compliance record, asserting that an
        # operator acted on a record their scope excludes is worse than a missing row. A global action targets
        # no record, and a selection wider than the cap is recorded as one row attached to none.
        def audited_record_ids(context, filter)
          return [] if context.collection.schema[:actions][@action_name].scope == Types::ActionScope::GLOBAL

          cap = ForestAdminAgent::AuditTrail::MAX_RECORDS_PER_OPERATION
          primary_keys = ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(context.collection)
          records = context.collection.list(
            context.caller, filter.override(page: Page.new(offset: 0, limit: cap + 1)), Projection.new(primary_keys)
          )

          return records.map { |record| Utils::Id.pack_id(context.collection, record) } if records.size <= cap

          ForestAdminAgent::AuditTrail.log_truncation(0, nil)
          []
        end

        def middleware_custom_action_approval_request_data(args)
          raise Http::Exceptions::UnprocessableError if args.dig(:params, :data, :attributes, :requester_id)

          if (signed_request = args.dig(:params, :data, :attributes, :signed_approval_request))
            args[:params][:data][:attributes][:signed_approval_request] = decode_signed_approval_request(signed_request)
          end

          args
        end

        def decode_signed_approval_request(signed_request)
          ForestAdminDatasourceToolkit::Utils::HashHelper.convert_keys(JWT.decode(
            signed_request,
            Facades::Container.cache(:env_secret),
            true,
            { algorithm: 'HS256' }
          )[0])
        end

        def get_record_selection(args, context, include_user_scope: true)
          attributes = args.dig(:params, :data, :attributes)

          # Match user filter + search + scope? + segment
          scope = include_user_scope ? context.permissions.get_scope(context.collection) : nil
          filter = Filter.new(
            condition_tree: ConditionTreeFactory.intersect(
              [
                scope,
                ForestAdminAgent::Utils::QueryStringParser.parse_condition_tree(
                  context.collection, args
                )
              ]
            )
          )

          # Restrict the filter to the selected records for single or bulk actions
          if context.collection.schema[:actions][@action_name].scope != Types::ActionScope::GLOBAL
            selection_ids = Utils::Id.parse_selection_ids(context.collection, args[:params])
            selected_ids = ConditionTreeFactory.match_ids(context.collection, selection_ids[:ids])
            selected_ids = selected_ids.inverse if selection_ids[:are_excluded]
            filter = filter.override(
              condition_tree: ConditionTreeFactory.intersect([filter.condition_tree, selected_ids])
            )
          end

          # Restrict the filter further for the "related data" page
          unless attributes[:parent_association_name].nil?
            relation = attributes[:parent_association_name]
            parent = context.datasource.get_collection(attributes[:parent_collection_name])
            parent_primary_key_values = Utils::Id.unpack_id(parent, attributes[:parent_collection_id])

            filter = FilterFactory.make_foreign_filter(parent, parent_primary_key_values, relation, context.caller,
                                                       filter)
          end

          filter
        end
      end
    end
  end
end
