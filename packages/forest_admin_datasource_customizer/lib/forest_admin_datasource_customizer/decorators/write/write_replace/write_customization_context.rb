module ForestAdminDatasourceCustomizer
  module Decorators
    module Write
      module WriteReplace
        class WriteCustomizationContext < ForestAdminDatasourceCustomizer::Context::CollectionCustomizationContext
          attr_reader :action, :record, :filter

          def initialize(collection, caller, action, record, filter = nil)
            super(collection, caller)
            @action = action
            @record = record
            @filter = filter
          end
        end
      end
    end
  end
end
