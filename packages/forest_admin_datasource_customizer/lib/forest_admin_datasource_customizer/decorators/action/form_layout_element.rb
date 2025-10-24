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

          def static?
            super && fields&.all?(&:static?)
          end

          private

          def validate_fields_presence!(options)
            return if options.key?(:fields)

            raise ForestAdminAgent::Http::Exceptions::BadRequestError, "Using 'fields' in a 'Row' configuration is mandatory"
          end

          def validate_no_layout_subfields!(fields)
            fields.each do |field|
              if (field.is_a?(DynamicField) && field.type == 'Layout') ||
                 (field.is_a?(Hash) && field[:type] == 'Layout')
                raise ForestAdminAgent::Http::Exceptions::UnprocessableError, "A 'Row' form element doesn't allow layout elements as subfields"
              end
            end
          end

          def instantiate_subfields(fields)
            FormFactory.build_elements(fields)
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
            @elements = instantiate_elements(options[:elements] || [])
          end

          def static?
            super && elements&.all?(&:static?)
          end

          private

          def validate_elements_presence!(options)
            return if options.key?(:elements)

            raise ForestAdminAgent::Http::Exceptions::BadRequestError, "Using 'elements' in a 'Page' configuration is mandatory"
          end

          def validate_no_page_elements!(elements)
            elements&.each do |element|
              if element[:component] == 'Page'
                raise ForestAdminAgent::Http::Exceptions::UnprocessableError, "'Page' component cannot be used within 'elements'"
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
