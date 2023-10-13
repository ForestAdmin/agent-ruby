module ForestAdminDatasourceToolkit
  module Components
    module Query
      class Filter
        attr_reader :condition_tree, :segment, :sort, :search, :search_extended, :page

        def initialize(condition_tree: nil, search: nil, search_extended: nil, segment: nil, sort: nil, page: nil)
          @condition_tree = condition_tree
          @search = search
          @search_extended = search_extended
          @segment = segment
          @sort = sort
          @page = page
        end
      end
    end
  end
end
