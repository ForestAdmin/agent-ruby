module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      module Context
        module After
          class HookAfterCreateContext < Hook::Context::Before::HookBeforeCreateContext
            attr_reader :record

            def initialize(collection, caller, data, record)
              super(collection, caller, data)
              @record = record
            end
          end
        end
      end
    end
  end
end
