module ForestAdminDatasourceToolkit
  module Decorators
    class DatasourceDecorator
      attr_reader :child_datasource

      def initialize(child_datasource, collection_decorator_class)
        @child_datasource = child_datasource
        @collection_decorator_class = collection_decorator_class
        @decorators = {}
      end

      def schema
        @child_datasource.schema
      end

      def collections
        @child_datasource.collections.transform_values { |c| get_collection(c.name) }
      end

      def live_query_connections
        @child_datasource.live_query_connections
      end

      def get_collection(name)
        @collections_by_name ||= {}
        @collections_by_name[name] ||= begin
          collection = @child_datasource.get_collection(name)
          @decorators[collection.name] ||= @collection_decorator_class.new(collection, self)
        end
      end

      def render_chart(caller, name, parameters = {})
        @child_datasource.render_chart(caller, name, parameters)
      end

      def execute_native_query(connection_name, query, binds)
        @child_datasource.execute_native_query(connection_name, query, binds)
      end
    end
  end
end
