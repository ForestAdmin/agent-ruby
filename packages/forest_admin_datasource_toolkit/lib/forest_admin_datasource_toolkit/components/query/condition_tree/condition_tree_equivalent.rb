module ForestAdminDatasourceToolkit
  module Components
    module Query
      module ConditionTree
        class ConditionTreeEquivalent
          def self.get_equivalent_tree(leaf, operators, column_type, timezone)
            operator = leaf.operator

            get_replacer(operator, operators, column_type).call(leaf, timezone)
          end

          def self.equivalent_tree?(operator, filter_operators, column_type)
            return true if filter_operators.include?(operator)

            !get_replacer(operator, filter_operators, column_type).nil?
          end

          class << self
            private

            def alternatives
              @alternatives ||= {}
            end

            def get_alternatives(operator)
              @alternatives ||= {}
              comparisons = Transforms::Comparisons.transforms[operator] || []
              pattern = Transforms::Pattern.transforms[operator] || []
              time = Transforms::Time.transforms[operator] || []

              @alternatives[operator] ||= comparisons.concat(pattern).concat(time)

              @alternatives[operator]
            end

            def get_replacer(operator, filter_operators, column_type, visited = [])
              return ->(leaf, _timezone) { leaf } if filter_operators.include?(operator)

              get_alternatives(operator)&.each do |alt|
                replacer = alt[:replacer]
                depends_on = alt[:depends_on]
                valid = alt[:for_types].nil? || alt[:for_types].include?(column_type)

                if valid && !visited.include?(alt)
                  depends_replacers = depends_on.map do |replacement|
                    get_replacer(replacement, filter_operators, column_type, visited + [alt])
                  end

                  if depends_replacers.all? { |r| !r.nil? }
                    return lambda { |leaf, timezone|
                      replacer.call(leaf).replace_leafs do |sub_leaf|
                        depends_replacers[depends_on.index(sub_leaf.operator)].call(sub_leaf, timezone)
                      end
                    }
                  end
                end
              end

              nil
            end
          end
        end
      end
    end
  end
end
