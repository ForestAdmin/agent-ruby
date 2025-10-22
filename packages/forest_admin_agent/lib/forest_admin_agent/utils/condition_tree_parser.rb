require 'jwt'
require 'active_support/time'

module ForestAdminAgent
  module Utils
    class ConditionTreeParser
      include ForestAdminAgent::Http::Exceptions
      include ForestAdminDatasourceToolkit::Exceptions
      include ForestAdminDatasourceToolkit::Utils
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes

      def self.from_plain_object(collection, filters)
        if leaf?(filters)
          operator = filters[:operator].titleize.tr(' ', '_').downcase
          value = parse_value(collection, filters)

          return ConditionTreeLeaf.new(filters[:field], operator, value)
        end

        if branch?(filters)
          aggregator = filters[:aggregator].capitalize
          conditions = filters[:conditions].map do |sub_tree|
            from_plain_object(collection, sub_tree)
          end

          return conditions.size == 1 ? conditions[0] : ConditionTreeBranch.new(aggregator, conditions)
        end

        raise BadRequestError.new(
          'Failed to instantiate condition tree: invalid filter format',
          details: { filters: filters }
        )
      end

      def self.parse_value(collection, leaf)
        schema = Collection.get_field_schema(collection, leaf[:field])

        if leaf[:operator] == Operators::IN && leaf[:field].is_a?(String)
          values = leaf[:value].split(',').map(&:strip)

          return values.map { |item| !%w[false 0 no].include?(item) } if schema.column_type == 'Boolean'

          return values.map(&:to_f).select { |item| item.is_a? Numeric } if schema.column_type == 'Number'

          return values
        end

        leaf[:value]
      end

      def self.leaf?(filters)
        filters.key?(:field) && filters.key?(:operator)
      end

      def self.branch?(filters)
        filters.key?(:aggregator) && filters.key?(:conditions)
      end
    end
  end
end
