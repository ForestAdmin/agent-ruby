module ForestAdminDatasourceCustomizer
  module Decorators
    module Search
      attr_reader :config

      class BaseSearchStrategy
        def initialize(config = {})
          @config = config
        end

        def build_condition_tree(_search_string, _extended_search, _context)
          raise NotImplementedError, 'Subclasses must implement build_condition_tree'
        end
      end
    end
  end
end
