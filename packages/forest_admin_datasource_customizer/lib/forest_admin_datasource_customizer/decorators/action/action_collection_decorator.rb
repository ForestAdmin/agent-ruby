module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      class ActionCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Components

        def initialize(child_collection, datasource)
          super
          @actions = {}
        end

        def add_action(name, action)
          action.build_elements
          action.validate_fields_ids
          @actions[name] = action

          mark_schema_as_dirty
        end

        def execute(caller, name, data, filter = nil)
          action = @actions[name]
          return @child_collection.execute(caller, name, data, filter) if action.nil?

          context = get_context(caller, action, data, filter)

          result_builder = ResultBuilder.new
          result = action.execute.call(context, result_builder)

          return result if result.is_a? Hash

          result_builder.success
        end

        def get_form(caller, name, data = nil, filter = nil, metas = {})
          action = @actions[name]
          return @child_collection.get_form(caller, name, data, filter, metas) if action.nil?
          return [] if action.form.nil?

          form_values = data || {}
          used = []
          context = get_context(caller, action, form_values, filter, used, metas[:change_field])

          dynamic_fields = action.form
          if metas[:search_field]
            # in the case of a search hook,
            # we don't want to rebuild all the fields. only the one searched
            dynamic_fields = dynamic_fields.select { |field| field.id == metas[:search_field] }
          end
          dynamic_fields = drop_defaults(context, dynamic_fields, form_values)
          dynamic_fields = drop_ifs(context, dynamic_fields) unless metas[:include_hidden_fields]

          fields = drop_deferred(context, metas[:search_values], dynamic_fields).compact

          fields.each do |field|
            next if field.type == 'Layout'

            if field.value.nil?
              # customer did not define a handler to rewrite the previous value => reuse current one.
              field.value = form_values[field.id]
            end

            # fields that were accessed through the context.get_form_value(x) getter should be watched.
            field.watch_changes = used.include?(field.id)
          end

          fields
        end

        def refine_schema(sub_schema)
          sub_schema[:actions] = @actions

          sub_schema
        end

        private

        def drop_defaults(context, fields, data)
          fields.map do |field|
            if field.type == 'Layout'
              field
            else
              drop_default(context, field, data)
            end
          end
        end

        def drop_default(context, field, data)
          data[field.id] = evaluate(context, field.default_value) unless data.key?(field.id)
          field.default_value = nil

          field
        end

        def drop_ifs(context, fields)
          if_values = fields.map { |field| !field.if_condition || evaluate(context, field.if_condition) }
          new_fields = fields.select.with_index { |_field, index| if_values[index] }
          new_fields.each do |field|
            field = field.dup
            field.if_condition = nil
          end

          new_fields
        end

        def drop_deferred(context, search_values, fields)
          new_fields = []
          fields.each do |field|
            field = field.dup
            field.instance_variables.each do |key|
              key = key.to_s.delete('@').to_sym

              next unless field.respond_to?(key)

              # call getter corresponding to the key and then set the evaluated value
              value = field.send(key)
              key = key.to_s.concat('=').to_sym

              search_value = field.type == 'Layout' ? nil : search_values&.dig(field.id)
              field.send(key, evaluate(context, value, search_value))
            end

            new_fields << Actions::ActionFieldFactory.build(field.to_h)
          end

          new_fields
        end

        def evaluate(context, value, search_value = nil)
          if value.respond_to?(:call)
            return value.call(context, search_value) if search_value

            return value.call(context)
          end

          value
        end

        def get_context(caller, action, form_values = [], filter = nil, used = [], change_field = nil)
          if action.scope == Types::ActionScope::SINGLE
            return Context::ActionContextSingle.new(self, caller, form_values, filter, used, change_field)
          end

          Context::ActionContext.new(self, caller, form_values, filter, used, change_field)
        end
      end
    end
  end
end
