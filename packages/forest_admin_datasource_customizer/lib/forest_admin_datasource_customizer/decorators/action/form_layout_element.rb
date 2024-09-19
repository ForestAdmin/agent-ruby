module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      module FormLayoutElement
        include Types

        class LayoutElement < BaseFormElement
          attr_accessor :if_condition, :component

          def initialize(component:, if_condition: nil, **kwargs)
            super(type: 'Layout', **kwargs)

            @component = component
            @if_condition = if_condition
          end
        end

        class SeparatorElement < LayoutElement
          def initialize(options)
            super(component: 'Separator', **options)
          end
        end
      end
    end
  end
end
