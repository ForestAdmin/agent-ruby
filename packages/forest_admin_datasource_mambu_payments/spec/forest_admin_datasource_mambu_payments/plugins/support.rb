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
  end
end
