module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      module FormLayoutElement
        include Types
        include ForestAdminDatasourceToolkit::Exceptions

        class ElementFactory
          def build_elements(form)
            form&.map do |field|
              if field.key? :widget
                build_widget(field)
              elsif field[:type] == 'Layout'
                build_layout_element(field)
              else
                DynamicField.new(**field)
              end
            end
          end
        end

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

            validate_elements_presence!(options)
            validate_no_page_elements!(options[:elements])
            @next_button_label = options[:next_button_label]
            @previous_button_label = options[:previous_button_label]
            @elements = instantiate_elements(options[:elements])
          end

          private

          def validate_elements_presence!(options)
            return if options.key?(:elements)

            raise ForestException, "Using 'elements' in a 'Page' configuration is mandatory"
          end

          def validate_no_page_elements!(elements)
            elements&.each do |element|
              if element[:component] == 'Page'
                raise ForestException, "'Page' component cannot be used within 'elements'"
              end
            end
          end

          def instantiate_elements(elements)
            FormFactory.build_elements(elements)
          end
        end
      end
    end
  end
end
