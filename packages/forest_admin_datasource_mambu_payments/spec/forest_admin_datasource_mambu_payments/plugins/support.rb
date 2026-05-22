module ForestAdminDatasourceMambuPayments
  module PluginSupport
    # Stand-in for an ActionContext: the executors only call get_records,
    # get_record, form_values, and (for write-backs) collection/filter.
    class FakeContext
      attr_reader :form_values, :collection, :filter

      def initialize(records: [], form_values: {}, collection: nil, filter: nil)
        @records = records
        @form_values = form_values
        @collection = collection
        @filter = filter
      end

      def get_records(_fields = [])
        @records
      end

      def get_record(_fields = [])
        @records.first || {}
      end
    end

    # Minimal CollectionCustomizer that records #add_action calls.
    class FakeCollection
      attr_reader :registered

      def initialize
        @registered = {}
      end

      def add_action(name, action)
        @registered[name] = action
      end
    end

    # Minimal CollectionCustomizer that records relation/import_field calls,
    # used by the relation plugin specs. Mirrors the public DSL shape exposed
    # by ForestAdminDatasourceCustomizer::CollectionCustomizer.
    class FakeRelationCollection
      attr_reader :imported_fields, :computed_fields, :many_to_one_relations, :one_to_many_relations,
                  :operator_handlers

      def initialize
        @imported_fields = {}
        @computed_fields = {}
        @many_to_one_relations = {}
        @one_to_many_relations = {}
        @operator_handlers = {}
      end

      def import_field(name, options = {})
        @imported_fields[name] = options
        self
      end

      def add_field(name, definition)
        @computed_fields[name] = definition
        self
      end

      def add_many_to_one_relation(name, foreign_collection, options = {})
        @many_to_one_relations[name] = options.merge(foreign_collection: foreign_collection)
        self
      end

      def add_one_to_many_relation(name, foreign_collection, options = {})
        @one_to_many_relations[name] = options.merge(foreign_collection: foreign_collection)
        self
      end

      def replace_field_operator(name, operator, &block)
        @operator_handlers[[name, operator]] = block
        self
      end
    end

    # Stand-in for the CollectionCustomizationContext passed to
    # replace_field_operator handlers. Exposes a `.datasource` whose
    # `get_collection(name).list(filter, projection)` returns a preloaded
    # set of records.
    class FakeOperatorContext
      def initialize(collections_data)
        @collections_data = collections_data
      end

      def datasource
        self
      end

      def get_collection(name)
        FakeOperatorCollection.new(@collections_data[name] || [])
      end
    end

    class FakeOperatorCollection
      def initialize(records)
        @records = records
      end

      def list(_filter, _projection)
        @records
      end
    end

    # Stand-in for a DatasourceCustomizer: records which collection was
    # customized and yields the matching FakeRelationCollection.
    class FakeDatasourceCustomizer
      attr_reader :collections

      def initialize
        @collections = Hash.new { |h, k| h[k] = FakeRelationCollection.new }
      end

      def customize_collection(name)
        yield(@collections[name])
      end
    end
  end
end
