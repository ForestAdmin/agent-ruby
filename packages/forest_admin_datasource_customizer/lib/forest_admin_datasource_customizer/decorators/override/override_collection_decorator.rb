module ForestAdminDatasourceCustomizer
  module Decorators
    module Override
      class OverrideCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include Context
        attr_reader :create_handler, :update_handler, :delete_handler

        def initialize(child_collection, datasource)
          super
          @create_handler = Handler.new
          @update_handler = Handler.new
          @delete_handler = Handler.new
        end

        def create(caller, data)
          if @create_handler
            context = CreateOverrideCustomizationContext.new(@child_collection, caller, data)
            return @create_handler.execute(context)
          end

          super
        end

        def add_create_handler(handler)
          @create_handler = handler
        end
      end
    end
  end
end
