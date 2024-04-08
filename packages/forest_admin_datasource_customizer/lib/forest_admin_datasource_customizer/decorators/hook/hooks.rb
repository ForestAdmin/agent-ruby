module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      class Hooks
        def initialize
          @before = []
          @after = []
        end

        def execute_before(context)
          @before.each { |hook| hook.call(context) }
        end

        def execute_after(context)
          @after.each { |hook| hook.call(context) }
        end

        def add_hook(position, hook)
          position == 'After' ? @after << hook : @before << hook
        end
      end
    end
  end
end
