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
          @actions[name] = action

          mark_schema_as_dirty
        end

        def execute(caller, name, data, filter = nil)
          action = @actions[name]
          return @child_collection.execute(caller, name, data, filter) if action.nil?

          context = get_context(caller, action, data, filter)

          result_builder = ResultBuilder.new
          result = action.execute.call(context, result_builder)

          result || result_builder.success
        end

        def get_form(caller, name, data = nil, filter = nil, metas = {})
          action = @actions[name]
          return @child_collection.get_form(caller, name, data, filter, metas) if action.nil?
          return [] if action.form.nil?

          form_values = data || {}
          used = []
          context = get_context(caller, action, form_values, filter, used, metas[:change_field])

          dynamic_fields = action.form
          dynamic_fields = drop_defaults(context, dynamic_fields, form_values)
          dynamic_fields = drop_ifs(context, dynamic_fields) unless metas[:include_hidden_fields]

          fields = drop_deferred(context, dynamic_fields)
          fields.each do |field|
            if field.value.nil?
              # customer did not define a handler to rewrite the previous value => reuse current one.
              field.value = form_values[field.label]
            end

            # fields that were accessed through the context.formValues.X getter should be watched.
            field.watch_changes = used.include?(field.label)
          end

          fields
        end

        def refine_schema(sub_schema)
          sub_schema[:actions] = @actions

          sub_schema
        end

        private

        def drop_defaults(context, fields, data)
          unvalued_fields = fields.reject { |field| data.key?(field.label) }
          defaults = unvalued_fields.map { |field| evaluate(context, field.default_value) }
          unvalued_fields.each_with_index { |field, index| data[field.label] = defaults[index] }

          fields.each { |field| field.default_value = nil }

          fields
        end

        def drop_ifs(context, fields)
          if_values = fields.map { |field| !field.if_condition || evaluate(context, field.if_condition) }
          new_fields = fields.select.with_index { |_field, index| if_values[index] }
          new_fields.each { |field| field.if_condition = nil }

          new_fields
        end

        def drop_deferred(context, fields)
          new_fields = []
          fields.each do |field|
            field.instance_variables.each do |key|
              key = key.to_s.delete('@').to_sym

              # call getter corresponding to the key and then set the evaluated value
              value = field.send(key)
              key = key.to_s.concat('=').to_sym

              field.send(key, evaluate(context, value))
            end

            new_fields << ActionField.new(**field.to_h)
          end

          new_fields
        end

        def evaluate(context, value)
          return value.call(context) if value.respond_to?(:call)

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
