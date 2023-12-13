module ForestAdminDatasourceToolkit
  module Decorators
    class CollectionDecorator
      attr_reader :datasource, :child_collection, :last_schema

      def initialize(child_collection, datasource)
        @child_collection = child_collection
        @datasource = datasource

        # When the child collection invalidates its schema, we also invalidate ours.
        # This is done like this, and not in the markSchemaAsDirty method, because we don't have
        # a reference to parent collections from children.
        return unless child_collection.is_a?(CollectionDecorator)

        original_child_mark_schema_as_dirty = child_collection.mark_schema_as_dirty
        child_collection.mark_schema_as_dirty = lambda {
          # Call the original method (the child)
          original_child_mark_schema_as_dirty.call(child_collection)

          # Invalidate our schema (the parent)
          mark_schema_as_dirty
        }
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

      def get_form(caller, name, data = nil, filter = nil, metas = nil)
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

      protected

      def mark_schema_as_dirty
        @last_schema = nil
      end

      def refine_filter(_caller, filter = nil)
        filter
      end

      def refine_schema(sub_schema)
        sub_schema
      end

      private

      def push_customization(customization)
        @stack.queue_customization(customization)

        self
      end
    end
  end
end
