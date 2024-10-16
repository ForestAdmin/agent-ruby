module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      class HookCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Components
        include Context

        attr_reader :hooks

        def initialize(child_collection, datasource)
          super
          @hooks = {
            'List' => Hooks.new,
            'Create' => Hooks.new,
            'Update' => Hooks.new,
            'Delete' => Hooks.new,
            'Aggregate' => Hooks.new
          }
        end

        def add_hook(position, type, hook)
          @hooks[type].add_handler(position, hook)
        end

        def create(caller, data)
          before_context = Before::HookBeforeCreateContext.new(@child_collection, caller, data)
          @hooks['Create'].execute_before(before_context)

          record = @child_collection.create(caller, before_context.data)

          after_context = After::HookAfterCreateContext.new(@child_collection, caller, data, record)
          @hooks['Create'].execute_after(after_context)

          record
        end

        def list(caller, filter, projection)
          before_context = Before::HookBeforeListContext.new(@child_collection, caller, filter, projection)
          @hooks['List'].execute_before(before_context)

          records = @child_collection.list(caller, before_context.filter, before_context.projection)

          after_context = After::HookAfterListContext.new(@child_collection, caller, filter, projection, records)
          @hooks['List'].execute_after(after_context)

          records
        end

        def update(caller, filter, patch)
          before_context = Before::HookBeforeUpdateContext.new(@child_collection, caller, filter, patch)
          @hooks['Update'].execute_before(before_context)

          @child_collection.update(caller, before_context.filter, before_context.patch)

          after_context = After::HookAfterUpdateContext.new(@child_collection, caller, filter, patch)
          @hooks['Update'].execute_after(after_context)
        end

        def delete(caller, filter)
          before_context = Before::HookBeforeDeleteContext.new(@child_collection, caller, filter)
          @hooks['Delete'].execute_before(before_context)

          @child_collection.delete(caller, before_context.filter)

          after_context = After::HookAfterDeleteContext.new(@child_collection, caller, filter)
          @hooks['Delete'].execute_after(after_context)
        end

        def aggregate(caller, filter, aggregation, limit = nil)
          before_context = Before::HookBeforeAggregateContext.new(@child_collection, caller, filter, aggregation, limit)
          @hooks['Aggregate'].execute_before(before_context)

          results = @child_collection.aggregate(
            caller,
            before_context.filter,
            before_context.aggregation,
            before_context.limit
          )

          after_context = After::HookAfterAggregateContext.new(
            @child_collection,
            caller,
            filter,
            aggregation,
            results,
            limit
          )
          @hooks['Aggregate'].execute_after(after_context)

          results
        end
      end
    end
  end
end
