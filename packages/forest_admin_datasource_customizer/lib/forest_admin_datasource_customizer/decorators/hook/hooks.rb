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

        # `prepend` puts the handler ahead of the ones already registered. `execute_after` stops at the
        # first exception, so a handler that must run whatever a sibling does (the audit trail recording a
        # write that already happened) cannot afford to be last.
        def add_handler(position, hook, prepend: false)
          handlers = position == 'After' ? @after : @before

          prepend ? handlers.unshift(hook) : handlers.push(hook)
        end
      end
    end
  end
end
