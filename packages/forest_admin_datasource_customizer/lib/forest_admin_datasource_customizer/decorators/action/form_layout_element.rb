module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      module FormLayoutElement
        include Types
        include ForestAdminDatasourceToolkit::Exceptions

        class LayoutElement < BaseFormElement
          attr_accessor :if_condition, :component

          def initialize(component:, if_condition: nil, **kwargs)
            super(type: 'Layout', **kwargs)
            @component = component
            @if_condition = if_condition
          end
        end

        class SeparatorElement < LayoutElement
          def initialize(**options)
            super(component: 'Separator', **options)
          end
        end

        class HtmlBlockElement < LayoutElement
          attr_accessor :content

          def initialize(content:, **options)
            super(component: 'HtmlBlock', **options)
            @content = content
          end
        end

        class RowElement < LayoutElement
          include ForestAdminDatasourceToolkit::Exceptions

          attr_accessor :fields

          def initialize(options)
            super(component: 'Row', **options)
            validate_fields_presence!(options)
            validate_no_layout_subfields!(options[:fields])
            @fields = instantiate_subfields(options[:fields] || [])
          end

          private

          def validate_fields_presence!(options)
            raise ForestException, "Using 'fields' in a 'Row' configuration is mandatory" unless options.key?(:fields)
          end

          def validate_no_layout_subfields!(fields)
            fields.each do |field|
              if (field.is_a?(DynamicField) && field.type == 'Layout') ||
                 (field.is_a?(Hash) && field[:type] == 'Layout')
                raise ForestException, "A 'Row' form element doesn't allow layout elements as subfields"
              end
            end
          end

          def instantiate_subfields(fields)
            fields.map do |field|
              DynamicField.new(**field.to_h)
            end
          end
        end

        class PageElement < LayoutElement
          include ForestAdminDatasourceToolkit::Exceptions

          attr_accessor :elements, :next_button_label, :previous_button_label

          def initialize(options)
            super(component: 'Page', **options)

            validate!(options)
            validate_button_labels!(options[:next_button_label], options[:previous_button_label])
            @next_button_label = options[:next_button_label]
            @previous_button_label = options[:previous_button_label]
            validate_elements!(options[:elements])
            @elements = instantiate_elements(options[:elements])
          end

          private

          def validate!(options)
            unless options.key?(:elements) && options.key?(:next_button_label) && options.key?(:previous_button_label)
              raise ForestException, "Using 'elements', 'next_button_label' or 'previous_button_label' in a 'Page' configuration is mandatory"
            end
          end

          def validate_button_labels!(next_button_label, previous_button_label)
            if next_button_label && !next_button_label.is_a?(Proc)
              raise ForestException, "The 'next_button_label' must be a Proc"
            end

            return unless previous_button_label && !previous_button_label.is_a?(Proc)

            raise ForestException, "The 'previous_button_label' must be a Proc"
          end

          def validate_elements!(elements)
            elements&.each do |element|
              if element[:component] == 'Page'
                raise ForestException, "'Page' component cannot be used within 'elements'"
              end
            end
          end

          def instantiate_elements(elements)
            elements.map do |element|
              ForestAdminDatasourceToolkit::Components::Actions::ActionFieldFactory.build(element)
            end
          end
        end
      end
    end
  end
end
