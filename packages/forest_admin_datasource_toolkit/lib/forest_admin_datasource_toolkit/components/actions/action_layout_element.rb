require 'active_support/core_ext/string/inflections'

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

        class HtmlBlockElement < BaseLayoutElement
          attr_reader :content

          def initialize(content:, **options)
            super(component: 'HtmlBlock', **options)
            @content = content
          end
        end

        class SeparatorElement < BaseLayoutElement
          def initialize(**options)
            super(component: 'Separator', **options)
          end
        end

        class RowElement < BaseLayoutElement
          attr_accessor :fields

          def initialize(fields:, **options)
            super(component: 'Row', **options)
            @fields = instantiate_subfields(fields)
          end

          def instantiate_subfields(fields)
            fields.map do |field|
              ActionField.new(**field.to_h)
            end
          end
        end

        class PageElement < BaseLayoutElement
          attr_accessor :elements, :next_button_label, :previous_button_label

          def initialize(elements:, previous_button_label:, next_button_label:, **options)
            super(component: 'Page', **options)
            @elements = elements
            @next_button_label = next_button_label
            @previous_button_label = previous_button_label
            @elements = instantiate_elements(elements)
          end

          def instantiate_elements(elements)
            elements.map do |element|
              ActionFieldFactory.build(element.to_h)
            end
          end
        end
      end
    end
  end
end
