module ForestAdminDatasourceCustomizer
  module Decorators
    module Override
      class OverrideCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include Context
        attr_reader :create_handler, :update_handler, :delete_handler

        def create(caller, data)
          if @create_handler
            context = CreateOverrideCustomizationContext.new(@child_collection, caller, data)
            return @create_handler.call(context)
          end

          super
        end

        def add_create_handler(handler)
          @create_handler = handler
        end

        def update(caller, filter, patch)
          if @update_handler
            context = UpdateOverrideCustomizationContext.new(@child_collection, caller, filter, patch)
            return @update_handler.call(context)
          end

          super
        end

        def add_update_handler(handler)
          @update_handler = handler
        end

        def delete(caller, filter)
          if @delete_handler
            context = DeleteOverrideCustomizationContext.new(@child_collection, caller, filter)
            return @delete_handler.call(context)
          end

          super
        end

        def add_delete_handler(handler)
          @delete_handler = handler
        end
      end
    end
  end
end
