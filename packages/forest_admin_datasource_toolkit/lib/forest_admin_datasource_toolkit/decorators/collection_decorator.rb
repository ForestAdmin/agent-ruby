module ForestAdminDatasourceToolkit
  module Decorators
    class CollectionDecorator < Collection
      attr_reader :datasource, :child_collection, :last_schema
      attr_writer :parent

      def initialize(child_collection, datasource)
        super
        @child_collection = child_collection
        @datasource = datasource

        child_collection.parent = self if child_collection.is_a?(CollectionDecorator)
      end

      def native_driver
        # TODO
      end

      def schema
        unless @last_schema
          sub_schema = @child_collection.schema
          @last_schema = refine_schema(sub_schema)
        end

        @last_schema
      end

      def name
        @child_collection.name
      end

      def execute(caller, name, data, filter = nil)
        refined_filter = refine_filter(caller, filter)

        @child_collection.execute(caller, name, data, refined_filter)
      end

      def get_form(caller, name, data = nil, filter = nil, metas = {})
        refined_filter = refine_filter(caller, filter)

        @child_collection.get_form(caller, name, data, refined_filter, metas)
      end

      def create(caller, data)
        @child_collection.create(caller, data)
      end

      def list(caller, filter = nil, projection = nil)
        refined_filter = refine_filter(caller, filter)

        @child_collection.list(caller, refined_filter, projection)
      end

      def update(caller, filter, patch)
        refined_filter = refine_filter(caller, filter)

        @child_collection.update(caller, refined_filter, patch)
      end

      def delete(caller, filter)
        refined_filter = refine_filter(caller, filter)

        @child_collection.delete(caller, refined_filter)
      end

      def aggregate(caller, filter, aggregation, limit = nil)
        refined_filter = refine_filter(caller, filter)

        @child_collection.aggregate(caller, refined_filter, aggregation, limit)
      end

      def render_chart(caller, name, record_id)
        @child_collection.render_chart(caller, name, record_id)
      end

      def mark_schema_as_dirty
        @last_schema = nil
        @parent&.mark_schema_as_dirty
      end

      protected

      def refine_filter(_caller, filter = nil)
        filter
      end

      def refine_schema(sub_schema)
        sub_schema
      end
    end
  end
end
