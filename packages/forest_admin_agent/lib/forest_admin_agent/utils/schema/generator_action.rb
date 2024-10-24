module ForestAdminAgent
  module Utils
    module Schema
      class GeneratorAction
        include ForestAdminDatasourceToolkit::Components

        DEFAULT_FIELDS = [
          {
            field: 'Loading...',
            label: 'Loading...',
            type: 'String',
            isReadOnly: true,
            defaultValue: 'Form is loading',
            value: nil,
            description: '',
            enums: nil,
            hook: nil,
            isRequired: false,
            reference: nil,
            widgetEdit: nil
          }
        ].freeze

        def self.get_action_slug(name)
          name.downcase.strip.tr(' ', '-').gsub(/[^\w-]/, '')
        end

        def self.build_schema(collection, name)
          action = collection.schema[:actions][name]
          action_index = collection.schema[:actions].keys.index(name)
          slug = get_action_slug(name)
          form_elements = extract_fields_and_layout(collection.get_form(nil, name))
          if action.static_form?
            fields = build_fields(collection, form_elements[:fields])
            layout = form_elements[:layout]
          else
            fields = DEFAULT_FIELDS
            layout = []
          end

          schema = {
            id: "#{collection.name}-#{action_index}-#{slug}",
            name: name,
            submitButtonLabel: action.submit_button_label,
            description: action.description,
            type: action.scope.downcase,
            baseUrl: nil,
            endpoint: "/forest/_actions/#{collection.name}/#{action_index}/#{slug}",
            httpMethod: 'POST',
            redirect: nil, # frontend ignores this attribute
            download: action.is_generate_file,
            fields: fields,
            hooks: {
              load: !action.static_form?,
              # Always registering the change hook has no consequences, even if we don't use it.
              change: ['changeHook']
            }
          }

          return schema if layout.all? { |element| element.component == 'Input' }

          schema[:layout] = build_layout(layout)

          schema
        end

        def self.build_layout_schema(field)
          field = field.to_h
          field.delete(:type)

          if field[:component] == 'Row'
            return {
              **field,
              component: field[:component].camelize(:lower),
              fields: field[:fields].map { |f| build_layout_schema(f) }
            }
          elsif field[:component] == 'Page'
            return {
              **field,
              component: field[:component].camelize(:lower),
              elements: field[:elements].map do |f|
                build_layout_schema(f)
              end
            }
          end

          { **field, component: field[:component].camelize(:lower) }
        end

        def self.build_field_schema(datasource, field)
          output = {
            description: field.description,
            isRequired: field.is_required,
            isReadOnly: field.is_read_only,
            field: field.id,
            label: field.label,
            value: ForestValueConverter.value_to_forest(field),
            widgetEdit: GeneratorActionFieldWidget.build_widget_options(field)
          }

          output[:hook] = 'changeHook' if field.respond_to?(:watch_changes) && field.watch_changes

          if ActionFields.collection_field?(field)
            collection = datasource.get_collection(field.collection_name)
            pk = ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(collection)[0]
            pk_schema = collection.schema[:fields][pk]

            output[:type] = pk_schema.column_type
            output[:reference] = "#{collection.name}.#{pk}"
          elsif field.type.end_with?('List')
            output[:type] = [field.type.delete_suffix('List')]
          else
            output[:type] = field.type
          end

          output[:enums] = field.enum_values if ActionFields.enum_field?(field) || ActionFields.enum_list_field?(field)

          output
        end

        def self.build_fields(collection, fields)
          if fields
            return fields.map do |field|
              new_field = build_field_schema(collection.datasource, field)
              new_field[:defaultValue] = new_field[:value]
              new_field.delete(:value)

              new_field
            end
          end

          []
        end

        def self.build_layout(elements)
          if elements.any? { |element| element.component != 'Input' }
            return elements.map do |element|
              build_layout_schema(element)
            end
          end

          []
        end

        def self.extract_fields_and_layout(form)
          fields = []
          layout = []
          form&.each do |element|
            if element.type == Actions::FieldType::LAYOUT
              if %w[Page Row].include?(element.component)
                extract = extract_fields_and_layout_for_component(element)
                layout << element
                fields.concat(extract[:fields])
              else
                layout << element
              end
            else
              fields << element
              # frontend rule
              layout << Actions::ActionLayoutElement::InputElement.new(component: 'Input', field_id: element.id)
            end
          end

          { fields: fields, layout: layout }
        end

        def self.extract_fields_and_layout_for_component(element)
          key = element.component == 'Page' ? :elements : :fields
          extract = extract_fields_and_layout(element.public_send(key))
          element.public_send(:"#{key}=", extract[:layout])
          extract
        end
      end
    end
  end
end
