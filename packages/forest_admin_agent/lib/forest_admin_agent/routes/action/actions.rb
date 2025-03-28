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
          @collection = collection
          super()
        end

        def setup_routes
          action_index = @collection.schema[:actions].keys.index(@action_name)
          slug = ForestAdminAgent::Utils::Schema::GeneratorAction.get_action_slug(@action_name)
          route_name = "forest_action_#{@collection.name}_#{action_index}_#{slug}"
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
          build(args)
          args = middleware_custom_action_approval_request_data(args)
          filter_for_caller = get_record_selection(args)
          get_record_selection(args, include_user_scope: false)

          @permissions.can_smart_action?(args, @collection, filter_for_caller)

          raw_data = args.dig(:params, :data, :attributes, :values)

          # As forms are dynamic, we don't have any way to ensure that we're parsing the data correctly
          # better send invalid data to the getForm() customer handler than to the execute() one.
          unsafe_data = Schema::ForestValueConverter.make_form_data_unsafe(raw_data)

          fields = @collection.get_form(
            @caller,
            @action_name,
            unsafe_data,
            filter_for_caller,
            { include_hidden_fields: true } # during execute, we need all possible fields
          )

          # Now that we have the field list, we can parse the data again.
          data = Schema::ForestValueConverter.make_form_data(
            @datasource,
            raw_data,
            fields.reject { |field| field.type == 'Layout' }
          )

          { content: @collection.execute(@caller, @action_name, data, filter_for_caller) }
        end

        def handle_hook_request(args = {})
          build(args)
          forest_fields = args.dig(:params, :data, :attributes, :fields)
          data = (Schema::ForestValueConverter.make_form_data_from_fields(@datasource, forest_fields) if forest_fields)
          filter = get_record_selection(args)
          search_values = {}
          forest_fields&.each { |field| search_values[field['field']] = field['searchValue'] }

          form = @collection.get_form(
            @caller,
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
              fields: form_elements[:fields].map { |f| Schema::GeneratorAction.build_field_schema(@collection, f) },
              layout: Schema::GeneratorAction.build_layout(form_elements[:layout])
            }
          }
        end

        private

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

        def get_record_selection(args, include_user_scope: true)
          attributes = args.dig(:params, :data, :attributes)

          # Match user filter + search + scope? + segment
          scope = include_user_scope ? @permissions.get_scope(@collection) : nil
          filter = Filter.new(
            condition_tree: ConditionTreeFactory.intersect(
              [
                scope,
                ForestAdminAgent::Utils::QueryStringParser.parse_condition_tree(
                  @collection, args
                )
              ]
            )
          )

          # Restrict the filter to the selected records for single or bulk actions
          if @collection.schema[:actions][@action_name].scope != Types::ActionScope::GLOBAL
            selection_ids = Utils::Id.parse_selection_ids(@collection, args[:params])
            selected_ids = ConditionTreeFactory.match_ids(@collection, selection_ids[:ids])
            selected_ids = selected_ids.inverse if selection_ids[:are_excluded]
            filter = filter.override(
              condition_tree: ConditionTreeFactory.intersect([filter.condition_tree, selected_ids])
            )
          end

          # Restrict the filter further for the "related data" page
          unless attributes[:parent_association_name].nil?
            relation = attributes[:parent_association_name]
            parent = @datasource.get_collection(attributes[:parent_collection_name])
            parent_id = Utils::Id.unpack_id(parent, attributes[:parent_collection_id])

            filter = FilterFactory.make_foreign_filter(parent, parent_id, relation, @caller, filter)
          end

          filter
        end
      end
    end
  end
end
