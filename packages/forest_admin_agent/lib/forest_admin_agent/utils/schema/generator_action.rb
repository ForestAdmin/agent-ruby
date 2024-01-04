module ForestAdminAgent
  module Utils
    module Schema
      class GeneratorAction
        DEFAULT_FIELDS = [
          {
            field: 'Loading...',
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
          schema = collection.schema[:actions][name]
          action_index = collection.schema[:actions].keys.index(name)
          slug = get_action_slug(name)
          fields = build_fields(collection, name, schema)

          {
            id: "#{collection.name}-#{action_index}-#{slug}",
            name: name,
            type: schema.scope.downcase,
            baseUrl: nil,
            endpoint: "/forest/_actions/#{collection.name}/#{action_index}/#{slug}",
            httpMethod: 'POST',
            redirect: nil, # frontend ignores this attribute
            download: schema.is_generate_file,
            fields: fields,
            hooks: {
              load: !schema.static_form?,
              # Always registering the change hook has no consequences, even if we don't use it.
              change: ['changeHook']
            }
          }
        end

        class << self
          private

          def build_field_schema(datasource, field)
            output = {
              description: field.description,
              isRequired: field.is_required,
              isReadOnly: field.is_read_only,
              field: field.label,
              value: ForestValueConverter.value_to_forest(field)
            }

            output[:hook] = 'changeHook' if field.watch_changes

            if ActionFields.collection_field?(field)
              collection = datasource.get_collection(field.collection_name)
              pk = ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(collection)
              pk_schema = collection.schema[:fields][pk]

              output[:type] = pk_schema.column_type
              output[:reference] = "#{collection.name}.#{pk}"
            elsif field.type.end_with?('List')
              output[:type] = [field.type.delete_suffix('List')]
            else
              output[:type] = field.type
            end

            if ActionFields.enum_field?(field) || ActionFields.enum_list_field?(field)
              output[:enums] = field.enum_values
            end

            output
          end

          def build_fields(collection, name, action)
            return DEFAULT_FIELDS unless action.static_form?

            fields = collection.get_form(nil, name)
            if fields
              return fields.map do |field|
                new_field = build_field_schema(collection.datasource, field)
                new_field[:default_value] = new_field[:value]
                new_field.delete(:value)

                new_field
              end
            end

            []
          end
        end
      end
    end
  end
end
