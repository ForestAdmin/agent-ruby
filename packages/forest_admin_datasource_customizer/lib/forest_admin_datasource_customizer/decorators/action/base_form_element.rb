module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      class BaseFormElement
        attr_accessor :type

        def initialize(
          type:,
          **_kwargs
        )
          @type = type
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
