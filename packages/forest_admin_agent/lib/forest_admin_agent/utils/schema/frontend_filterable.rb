module ForestAdminAgent
  module Utils
    module Schema
      class FrontendFilterable
        def self.filterable?(operator)
          operator && !operator.empty?
        end
      end
    end
  end
end
