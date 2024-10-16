module ForestAdminDatasourceToolkit
  module Components
    module Actions
      class ActionField
        attr_accessor :value, :watch_changes
        attr_reader :type, :label, :description, :is_required, :is_read_only, :enum_values, :collection_name, :widget,
                    :placeholder, :id

        def initialize(
          type:,
          label: nil,
          id: nil,
          description: nil,
          is_required: false,
          is_read_only: false,
          value: nil,
          enum_values: nil,
          collection_name: nil,
          watch_changes: false,
          placeholder: nil,
          **_kwargs
        )
          @type = type
          @label = label
          @id = id
          @description = description
          @is_required = is_required
          @is_read_only = is_read_only
          @value = value
          @enum_values = enum_values
          @collection_name = collection_name
          @watch_changes = watch_changes
          @widget = nil
          @placeholder = placeholder
        end

        def watch_changes?
          @watch_changes
        end

        def to_h
          result = {}
          instance_variables.each do |attribute|
            result[attribute.to_s.delete('@').to_sym] = instance_variable_get(attribute)
          end

          result
        end
      end
    end
  end
end
