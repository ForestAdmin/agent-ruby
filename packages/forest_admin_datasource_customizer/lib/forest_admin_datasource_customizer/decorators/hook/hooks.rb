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
          instrument('before', context) { @before.each { |hook| hook.call(context) } }
        end

        def execute_after(context)
          instrument('after', context) { @after.each { |hook| hook.call(context) } }
        end

        def add_handler(position, hook)
          position == 'After' ? @after << hook : @before << hook
        end

        private

        def instrument(position, context, &block)
          hooks = position == 'before' ? @before : @after
          return yield if hooks.empty?

          ForestAdminDatasourceToolkit::Monitoring.instrument(
            'hook', { collection: context.collection.name, operation: @type, position: position },
            caller: context.caller, &block
          )
        end
      end
    end
  end
end
