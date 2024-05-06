module ForestAdminDatasourceCustomizer
  module Decorators
    module Override
      class Handler
        def execute(context)
          context.call
        end
      end
    end
  end
end
