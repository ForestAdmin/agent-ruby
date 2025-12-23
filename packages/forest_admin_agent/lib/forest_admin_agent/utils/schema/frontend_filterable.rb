module ForestAdminAgent
  module Utils
    module Schema
      class FrontendFilterable
        def self.filterable?(operator)
          operator && !operator.empty?
        end

        def self.sort_operators(operators)
          return operators unless operators.is_a?(Array)

          operators.sort
        end
      end
    end
  end
end
