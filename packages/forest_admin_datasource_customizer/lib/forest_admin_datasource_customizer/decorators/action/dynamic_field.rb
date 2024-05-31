module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      class DynamicField
        attr_accessor :type, :label, :description, :is_required, :is_read_only, :if_condition, :value, :default_value,
                      :collection_name, :enum_values, :placeholder

        def initialize(
          type:,
          label:,
          description: nil,
          is_required: false,
          is_read_only: false,
          if_condition: nil,
          value: nil,
          default_value: nil,
          collection_name: nil,
          enum_values: nil,
          placeholder: nil,
          **_kwargs
        )
          @type = type
          @label = label
          @description = description
          @is_required = is_required
          @is_read_only = is_read_only
          @if_condition = if_condition
          @value = value
          @default_value = default_value
          @collection_name = collection_name
          @enum_values = enum_values
          @placeholder = placeholder
        end

        def static?
          instance_variables.all? { |attribute| !instance_variable_get(attribute).respond_to?(:call) }
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
