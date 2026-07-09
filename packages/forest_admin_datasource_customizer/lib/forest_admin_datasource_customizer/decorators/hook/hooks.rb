module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      class Hooks
        attr_reader :before, :after

        def initialize(type = nil)
          @type = type
          @before = []
          @after = []
        end

        def execute_before(context)
          instrument('before') { @before.each { |hook| hook.call(context) } }
        end

        def execute_after(context)
          instrument('after') { @after.each { |hook| hook.call(context) } }
        end

        def add_handler(position, hook)
          position == 'After' ? @after << hook : @before << hook
        end

        private

        def instrument(position, &block)
          hooks = position == 'before' ? @before : @after
          return block.call if hooks.empty?

          ForestAdminDatasourceToolkit::Monitoring.instrument(
            'hook', { operation: @type, position: position }, &block
          )
        end
      end
    end
  end
end
