module ForestAdminDatasourceCustomizer
  module Decorators
    module Segment
      class SegmentCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Decorators
        include ForestAdminDatasourceToolkit::Validations
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

        attr_reader :segments

        def initialize(child_collection, datasource)
          super
          @segments = {}
        end

        def add_segment(name, definition)
          @segments[name] = definition

          mark_schema_as_dirty
        end

        def refine_schema(sub_schema)
          sub_schema[:segments] = sub_schema[:segments].merge(@segments)

          sub_schema
        end

        def refine_filter(caller, filter = nil)
          return nil unless filter

          condition_tree = filter.condition_tree
          segment = filter.segment

          if segment && @segments.key?(segment)
            definition = @segments[segment]

            result = if definition.respond_to? :call
                       definition.call(Context::CollectionCustomizationContext.new(self, caller))
                     else
                       definition
                     end

            condition_tree_segment = if result.is_a? Nodes::ConditionTree
                                       result
                                     else
                                       ConditionTreeFactory.from_plain_object(result)
                                     end

            ConditionTreeValidator.validate(condition_tree_segment, self)

            condition_tree = ConditionTreeFactory.intersect([condition_tree_segment, filter.condition_tree])
            segment = nil
          end

          filter.override(condition_tree: condition_tree, segment: segment)
        end
      end
    end
  end
end
