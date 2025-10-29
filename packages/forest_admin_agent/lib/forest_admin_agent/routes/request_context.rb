module ForestAdminAgent
  module Routes
    # RequestContext holds request-specific data that should not be shared between concurrent requests.
    # This prevents race conditions when route instances are reused across multiple requests.
    class RequestContext
      attr_accessor :datasource, :collection, :child_collection, :caller, :permissions

      def initialize(datasource: nil, collection: nil, child_collection: nil, caller: nil, permissions: nil)
        @datasource = datasource
        @collection = collection
        @child_collection = child_collection
        @caller = caller
        @permissions = permissions
      end
    end
  end
end
