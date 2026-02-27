module ForestAdminDatasourceCustomizer
  module Context
    module RelaxedWrappers
      class RelaxedCollection
        include ForestAdminDatasourceToolkit::Components::Query

        def initialize(collection, caller)
          @collection = collection
          @caller = caller
        end

        def native_driver(&block)
          @collection.native_driver(&block)
        end

        def schema
          @collection.schema
        end

        def execute(name, form_values = {}, filter = nil)
          @collection.execute(@caller, name, form_values, filter)
        end

        def get_form(name, data = nil, filter = nil, metas = {})
          @collection.get_form(@caller, name, data, filter, metas)
        end

        def create(data)
          @collection.create(@caller, data)
        end

        def list(filter, projection)
          @collection.list(@caller, filter, projection)
        end

        def update(filter, data)
          @collection.update(@caller, filter, data)
        end

        def delete(filter)
          @collection.delete(@caller, filter)
        end

        def aggregate(filter, aggregation, limit = nil)
          @collection.aggregate(@caller, filter, aggregation, limit)
        end
      end
    end
  end
end
