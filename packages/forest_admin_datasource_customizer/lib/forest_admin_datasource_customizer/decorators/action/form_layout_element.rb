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
              ForestAdminDatasourceToolkit::Components::Actions::ActionFieldFactory.build(field.to_h)
            end
          end
        end
      end
    end
  end
end
