module ForestAdminDatasourceCustomizer
  module Decorators
    module Override
      module Context
        class UpdateOverrideCustomizationContext < ForestAdminDatasourceCustomizer::Context::CollectionCustomizationContext
          attr_reader :filter, :patch

          def initialize(collection, caller, filter, patch)
            super(collection, caller)
            @filter = filter
            @patch = patch
          end

          def _filter=(value)
            @filter = value
          end

          def _patch=(value)
            @patch = value
          end
        end
      end
    end
  end
end
