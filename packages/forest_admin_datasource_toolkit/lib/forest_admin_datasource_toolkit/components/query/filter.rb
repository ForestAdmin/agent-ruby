module ForestAdminDatasourceToolkit
  module Components
    module Query
      class Filter
        attr_reader :condition_tree, :segment, :sort, :search, :search_extended, :page

        def initialize(
          condition_tree: nil,
          search: nil,
          search_extended: nil,
          segment: nil,
          sort: nil,
          page: nil
        )
          @condition_tree = condition_tree
          @search = search
          @search_extended = search_extended
          @segment = segment
          @sort = sort
          @page = page
        end

        def to_h(deeply: true)
          {
            condition_tree: deeply && !@condition_tree.nil? ? @condition_tree.to_h : @condition_tree,
            search: @search,
            search_extended: @search_extended,
            segment: @segment,
            sort: @sort,
            page: deeply && !page.nil? ? @page.to_h : @page
          }
        end

        def nestable?
          !@search && !@segment
        end

        def override(args)
          args = to_h(deeply: false).merge(args)

          Filter.new(**args)
        end

        def nest(prefix)
          raise ForestException, "Filter can't be nested" unless nestable?

          override(condition_tree: @condition_tree&.nest(prefix))
        end
      end
    end
  end
end
