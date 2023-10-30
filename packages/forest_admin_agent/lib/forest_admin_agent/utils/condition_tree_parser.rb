require 'jwt'
require 'active_support/time'

module ForestAdminAgent
  module Utils
    class ConditionTreeParser
      include ForestAdminDatasourceToolkit::Exceptions
      include ForestAdminDatasourceToolkit::Utils
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes


      def self.from_plain_object(collection, filters)
        if leaf?(filters)
          operator = filters['operator'].titleize.gsub(' ', '_')
          value = parse_value(collection, filters)

          return ConditionTreeLeaf.new(filters['field'], operator, value)
        end

        if (branch?(filters))
          aggregator = filters['aggregator'].capitalize
          conditions = []
          filters['conditions'].each do | sub_tree |
            conditions << from_plain_object(collection, sub_tree)
          end

          return conditions.size != 1 ? ConditionTreeBranch.new(aggregator, conditions) : conditions[0]
        end

        raise ForestException.new('Failed to instantiate condition tree')
      end

      private

      def self.parse_value(collection, leaf)
        schema = Collection.get_field_schema(collection, leaf['field'])
        operator = leaf['operator'].titleize.gsub(' ', '_')

        if (operator == Operators::IN && leaf['field'].is_a?(String))
          values = leaf['value'].split(',').map { |item| item.strip }

          if schema.column_type == 'Boolean'
            return values.map { |item| ! %w[false 0 no].include?(item) }
          end

          if schema.column_type == 'Number'
            return values.map { |item| item.to_f }.select { |item| item.is_a? Numeric }
          end
        end

        leaf['value']
      end

      def self.leaf?(filters)
        filters.key?('field') && filters.key?('operator')
      end

      def self.branch?(filters)
        filters.key?('aggregator') && filters.key?('conditions')
      end
    end
  end
end
