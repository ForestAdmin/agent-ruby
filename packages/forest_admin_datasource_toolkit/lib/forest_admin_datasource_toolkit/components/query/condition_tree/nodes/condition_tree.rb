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

            def some_leaf(&handler)
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
                replace_leafs { |leaf| leaf.override(field: "#{prefix}:#{leaf.field}") }
              end
            end

            def unnest
              prefix = nil
              some_leaf do |leaf|
                prefix = leaf.field.split(':').first
                false
              end
              unless every_leaf { |leaf| leaf.field.start_with?(prefix) }
                raise ForestException, 'Cannot unnest condition tree.'
              end

              replace_leafs { |leaf| leaf.override(field: leaf.field[(prefix.length + 1)..]) }
            end

            def replace_fields
              replace_leafs { |leaf| leaf.override(field: yield(leaf.field)) }
            end
          end
        end
      end
    end
  end
end
