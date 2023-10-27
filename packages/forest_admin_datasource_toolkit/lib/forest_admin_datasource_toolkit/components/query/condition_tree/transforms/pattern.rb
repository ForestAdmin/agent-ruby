module ForestAdminDatasourceToolkit
  module Components
    module Query
      module ConditionTree
        module Transforms
          class Pattern
            def self.likes(get_pattern, case_sensitive)
              operator = case_sensitive ? Operators::LIKE : Operators::I_LIKE

              {
                dependsOn: [operator],
                forTypes: ['String'],
                replacer: ->(leaf) { leaf.override(operator: operator, value: get_pattern.call(leaf.value)) }
              }
            end

            def self.match(case_sensitive)
              {
                dependsOn: [Operators::MATCH],
                forTypes: ['String'],
                replacer: lambda { |leaf|
                  regex = leaf.value.gsub(/([\.\\\+\*\?\[\^\]\$\(\)\{\}\=\!\<\>\|\:\-])/, '\\\\\1')
                  regex.tr!(/%/, '.*')
                  regex.tr!('_', '.')

                  leaf.override(operator: Operators::MATCH, value: /^#{regex}$/ + (case_sensitive ? '' : 'i'))
                }
              }
            end

            def self.transforms
              {
                Operators::CONTAINS => [likes(->(value) { "%#{value}%" }, true)],
                Operators::STARTS_WITH => [likes(->(value) { "#{value}%" }, true)],
                Operators::ENDS_WITH => [likes(->(value) { "%#{value}" }, true)],
                Operators::I_CONTAINS => [likes(->(value) { "%#{value}%" }, false)],
                Operators::I_STARTS_WITH => [likes(->(value) { "#{value}%" }, false)],
                Operators::I_ENDS_WITH => [likes(->(value) { "%#{value}" }, false)],
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
