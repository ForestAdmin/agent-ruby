module ForestAdminDatasourceToolkit
  module Components
    module Query
      module ConditionTree
        module Transforms
          class Pattern
            def self.likes(get_pattern, case_sensitive)
              operator = case_sensitive ? Operators::LIKE : Operators::I_LIKE

              {
                depends_on: [operator],
                for_types: ['String'],
                replacer: proc { |leaf| leaf.override(operator: operator, value: get_pattern.call(leaf.value)) }
              }
            end

            def self.match(case_sensitive)
              {
                depends_on: [Operators::MATCH],
                for_types: ['String'],
                replacer: proc { |leaf|
                  regex = leaf.value.gsub(/([\.\\\+\*\?\[\^\]\$\(\)\{\}\=\!\<\>\|\:\-])/, '\\\\\1')
                  regex.gsub!('%', '.*')
                  regex.tr!('_', '.')

                  leaf.override(operator: Operators::MATCH, value: "/^#{regex}$/#{case_sensitive ? "" : "i"}")
                }
              }
            end

            def self.transforms
              {
                Operators::CONTAINS => [likes(proc { |value| "%#{value}%" }, true)],
                Operators::STARTS_WITH => [likes(proc { |value| "#{value}%" }, true)],
                Operators::ENDS_WITH => [likes(proc { |value| "%#{value}" }, true)],
                Operators::I_CONTAINS => [likes(proc { |value| "%#{value}%" }, false)],
                Operators::I_STARTS_WITH => [likes(proc { |value| "#{value}%" }, false)],
                Operators::I_ENDS_WITH => [likes(proc { |value| "%#{value}" }, false)],
                Operators::I_LIKE => [match(false)],
                Operators::LIKE => [match(true)]
              }
            end
          end
        end
      end
    end
  end
end
