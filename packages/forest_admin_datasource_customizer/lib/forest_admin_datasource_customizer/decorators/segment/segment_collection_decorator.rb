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

        def refine_filter(_caller, filter = nil)
          return nil unless filter

          condition_tree = filter.condition_tree
          segment = filter.segment

          if segment && @segments.key?(segment)
            condition_tree = compute_segment(segment, filter)
            segment = nil
          elsif filter.segment_query
            condition_tree = compute_live_query_segment(filter)
            segment = nil
          end

          filter.override(condition_tree: condition_tree, segment: segment)
        end
      end

      def compute_segment(segment_name, filter)
        definition = @segments[segment_name]

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

        ConditionTreeFactory.intersect([condition_tree_segment, filter.condition_tree])
      end

      def compute_live_query_segment(filter)
        # TODO: add live query checker
        ids = @child_collection.execute_native_query(filter.segment_query)
                               .to_a
                               .map(&:values)
        condition_tree_segment = ConditionTreeFactory.match_ids(@child_collection, ids)
        ConditionTreeValidator.validate(condition_tree_segment, self)

        ConditionTreeFactory.intersect([condition_tree_segment, filter.condition_tree])
      end
    end
  end
end
