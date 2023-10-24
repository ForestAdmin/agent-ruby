module ForestAdminDatasourceToolkit
  module Components
    module Query
      module ConditionTree
        module Nodes
          class ConditionTree
            include ForestAdminDatasourceToolkit::Exceptions

            def inverse
              raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
            end

            def replace_leafs(&handler)
              raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
            end

            def match(record, collection, timezone)
              raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
            end

            def for_each_leaf(handler)
              raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
            end

            def every_leaf(&handler)
              raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
            end

            def some_leaf(handler)
              raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
            end

            def projection
              raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
            end

            def apply(records, collection, timezone)
              records.select { |record| match(record, collection, timezone) }
            end

            def nest(prefix)
              if prefix.empty?
                self
              else
                replaceLeafs { |leaf| leaf.override(field: "#{prefix}:#{leaf.getField}") }
              end
            end

            def unnest
              field = if is_a?(ConditionTreeBranch)
                        getConditions[0].getField
                      else
                        getField
                      end
              prefix = field.split(':')[0]

              unless every_leaf { |leaf| leaf.getField.start_with?("#{prefix}:") }
                raise ForestException, 'Cannot unnest condition tree.'
              end

              replace_leafs { |leaf| leaf.override(field: leaf.getField[(prefix.length + 1)..]) }
            end

            def replace_fields(handler)
              replace_leafs { |leaf| leaf.override(field: handler.call(leaf.getField)) }
            end
          end
        end
      end
    end
  end
end
