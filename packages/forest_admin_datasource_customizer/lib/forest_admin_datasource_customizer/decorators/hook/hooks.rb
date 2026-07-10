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

          payload = { collection: context.collection.name, operation: @type, position: position }
                    .merge(ForestAdminDatasourceToolkit::Monitoring.caller_payload(context.caller))
          ForestAdminDatasourceToolkit::Monitoring.instrument('hook', payload, &block)
        end
      end
    end
  end
end
