module ForestAdminDatasourceToolkit
  module Components
    module Query
      module ConditionTree
        class ConditionTreeEquivalent
          def self.get_equivalent_tree(leaf, operators, column_type, timezone)
            replacer = get_replacer(leaf.operator, operators, column_type)

            replacer&.call(leaf, timezone)
          end

          def self.equivalent_tree?(operator, filter_operators, column_type)
            return true if filter_operators.include?(operator)

            !get_replacer(operator, filter_operators, column_type).nil?
          end

          def self.get_alternatives(operator)
            @alternatives ||= {}
            @alternatives ||= Comparisons.equality_transforms + Pattern.pattern_transforms + Time.time_transforms

            @alternatives[operator]
          end

          private_class_method :get_alternatives

          private

          def alternatives
            @alternatives ||= {}
          end

          def get_replacer(operator, filter_operators, column_type, visited = [])
            return ->(leaf) { leaf } if filter_operators.include?(operator)

            alternatives.each do |alt|
              replacer = alt['replacer']
              depends_on = alt['dependsOn']

              valid = !alt.key?('forTypes') ||
                      (alt.key?('forTypes') && alt['forTypes'].all? do |type|
                         ForestAdminDatasourceToolkit::Schema::PrimitiveType.all.include?(type)
                       end)

              next unless valid && !visited.include?(alt)

              depends_replacer = depends_on.to_h do |replacement|
                [replacement, get_replacer(replacement, filter_operators, column_type, visited + [alt])]
              end

              if depends_replacer.all? { |r| !r.nil? }
                return lambda { |leaf, timezone|
                  condition_tree = replacer.call(leaf, timezone)

                  condition_tree.replace_leafs do |sub_leaf|
                    closure = depends_replacer[sub_leaf.operator]

                    closure.call(sub_leaf, timezone)
                  end
                }
              end
            end

            nil
          end
        end
      end
    end
  end
end
