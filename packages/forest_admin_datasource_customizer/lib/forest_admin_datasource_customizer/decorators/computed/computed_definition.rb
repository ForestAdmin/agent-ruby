module ForestAdminDatasourceCustomizer
  module Decorators
    module Computed
      class ComputedDefinition
        attr_reader :column_type, :dependencies, :default_value, :enum_values

        def initialize(column_type:, dependencies:, values:, default_value: nil, enum_values: nil)
          @column_type = column_type
          @dependencies = dependencies
          @values = values
          @default_value = default_value
          @enum_values = enum_values
        end

        def get_values(*args)
          @values.call(*args)
        end
      end
    end
  end
end
