module ForestAdminDatasourceCustomizer
  module Decorators
    module Override
      module Context
        class DeleteOverrideCustomizationContext < ForestAdminDatasourceCustomizer::Context::CollectionCustomizationContext
          attr_reader :filter

          def initialize(collection, caller, filter)
            super(collection, caller)
            @filter = filter
          end

          def _filter=(value)
            @filter = value
          end
        end
      end
    end
  end
end
