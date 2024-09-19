module ForestAdminDatasourceToolkit
  module Components
    module Actions
      module ActionLayoutElement
        class BaseLayoutElement
          attr_reader :type, :component

          def initialize(component:, **_kwargs)
            @type = FieldType::LAYOUT
            @component = component
          end

          def to_h
            result = {}
            instance_variables.each do |attribute|
              result[attribute.to_s.delete('@').camelize(:lower).to_sym] = instance_variable_get(attribute)
            end

            result
          end
        end

        class InputElement < BaseLayoutElement
          attr_reader :field_id

          def initialize(field_id:, **options)
            super(component: 'Separator', **options)
            @field_id = field_id
          end
        end

        class SeparatorElement < BaseLayoutElement
          def initialize(**options)
            super(component: 'Separator', **options)
          end
        end
      end
    end
  end
end
