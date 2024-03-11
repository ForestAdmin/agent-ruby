module ForestAdminDatasourceToolkit
  module Components
    module Query
      class Page
        attr_reader :offset, :limit

        def initialize(offset:, limit:)
          @offset = offset
          @limit = limit
        end

        def apply(records)
          end_index = @limit ? @offset + @limit : nil
          records[@offset...end_index]
        end
      end
    end
  end
end
