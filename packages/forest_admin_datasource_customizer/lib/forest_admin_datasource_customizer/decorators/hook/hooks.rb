module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      class Hooks
        attr_reader :before, :after

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

        def add_handler(position, hook)
          position == 'after' ? @after << hook : @before << hook
        end
      end
    end
  end
end
