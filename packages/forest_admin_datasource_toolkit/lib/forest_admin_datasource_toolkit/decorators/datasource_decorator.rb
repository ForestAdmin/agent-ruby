module ForestAdminDatasourceToolkit
  module Decorators
    class DatasourceDecorator
      def initialize(child_datasource, collection_decorator_class)
        @child_datasource = child_datasource
        @collection_decorator_class = collection_decorator_class
        @decorators = {}
      end

      def collections
        @child_datasource.collections.transform_values { |c| get_collection(c.name) }
      end

      def get_collection(name)
        collection = @child_datasource.get_collection(name)
        unless @decorators.key?(collection.name)
          @decorators[collection.name] = @collection_decorator_class.new(collection, self)
        end

        @decorators[collection.name]
      end

      def render_chart(caller, name)
        @child_datasource.render_chart(caller, name)
      end
    end
  end
end
