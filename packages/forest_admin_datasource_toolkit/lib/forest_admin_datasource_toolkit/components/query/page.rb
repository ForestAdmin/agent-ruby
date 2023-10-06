module ForestAdminDatasourceToolkit
  module Components
    module Query
      class Page
        attr_reader :offset, :limit

        def initialize(offset:, limit:)
          @offset = offset
          @limit = limit
        end
      end
    end
  end
end
