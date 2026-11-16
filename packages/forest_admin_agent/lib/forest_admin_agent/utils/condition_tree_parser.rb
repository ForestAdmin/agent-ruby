require 'jwt'
require 'active_support/time'

module ForestAdminAgent
  module Utils
    class ConditionTreeParser
      include ForestAdminAgent::Http::Exceptions
      include ForestAdminDatasourceToolkit::Utils
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes

      def self.from_plain_object(collection, filters)
        parse(collection, filters, root: true)
      end

      def self.parse(collection, filters, root:)
        if leaf?(filters)
          operator = filters[:operator].titleize.tr(' ', '_').downcase
          value = parse_value(collection, filters.merge(operator: operator))

          return ConditionTreeLeaf.new(filters[:field], operator, value)
        end

        if branch?(filters)
          # An empty nested group has no safe reading: an empty Or matches nothing, an empty And everything.
          # Keeping or dropping it can flip a bulk action between no records and the whole collection.
          raise BadRequestError, 'A nested group of conditions cannot be empty' if !root && filters[:conditions].empty?

          aggregator = filters[:aggregator].capitalize
          conditions = filters[:conditions].map do |sub_tree|
            parse(collection, sub_tree, root: false)
          end

          return conditions.size == 1 ? conditions[0] : ConditionTreeBranch.new(aggregator, conditions)
        end

        raise BadRequestError, 'Failed to instantiate condition tree'
      end

      def self.parse_value(collection, leaf)
        schema = Collection.get_field_schema(collection, leaf[:field])
        expected_type = get_expected_type_for_condition(leaf, schema)

        cast_to_type(leaf[:value], expected_type)
      end

      def self.get_expected_type_for_condition(leaf, schema)
        operators_expecting_number = [
          Operators::SHORTER_THAN,
          Operators::LONGER_THAN,
          Operators::AFTER_X_HOURS_AGO,
          Operators::BEFORE_X_HOURS_AGO,
          Operators::PREVIOUS_X_DAYS,
          Operators::PREVIOUS_X_DAYS_TO_DATE
        ]

        return 'Number' if operators_expecting_number.include?(leaf[:operator])

        if [Operators::IN, Operators::NOT_IN, Operators::INCLUDES_ALL].include?(leaf[:operator])
          return [schema.column_type]
        end

        schema.column_type
      end

      def self.cast_to_type(value, expected_type)
        return value if value.nil?

        if expected_type.is_a?(Array)
          items = value.is_a?(String) ? value.split(',').map(&:strip) : value
          filter_fn = expected_type[0] == 'Number' ? ->(item) { item.is_a?(Numeric) } : ->(_) { true }

          return value unless items.is_a?(Array)

          return items.map { |item| cast_to_type(item, expected_type[0]) }.select(&filter_fn)
        end

        case expected_type
        when 'String', 'Dateonly', 'Date'
          value.to_s
        when 'Number'
          value.to_f
        when 'Boolean'
          !%w[false 0 no].include?(value.to_s)
        else
          value
        end
      end

      def self.leaf?(filters)
        filters.is_a?(Hash) && filters.key?(:field) && filters.key?(:operator)
      end

      def self.branch?(filters)
        filters.is_a?(Hash) && filters.key?(:aggregator) && filters[:conditions].is_a?(Array)
      end
    end
  end
end
