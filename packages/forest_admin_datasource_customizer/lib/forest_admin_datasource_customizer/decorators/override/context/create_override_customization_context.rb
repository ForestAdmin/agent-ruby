module ForestAdminDatasourceCustomizer
  module Decorators
    module Override
      module Context
        class CreateOverrideCustomizationContext < ForestAdminDatasourceCustomizer::Context::CollectionCustomizationContext
          attr_reader :data

          def initialize(collection, caller, data)
            super(collection, caller)
            @data = data
          end
        end
      end
    end
  end
end
