module ForestAdminDatasourceToolkit
  module Components
    module Query
      module ConditionTree
        class ConditionTreeFactory
          include Nodes
          include ForestAdminDatasourceToolkit::Exceptions

          def self.match_none
            ConditionTreeBranch.new('Or', [])
          end

          def self.match_records(collection, records)
            ids = records.map { |record| ForestAdminDatasourceToolkit::Utils::Record.primary_keys(collection, record) }

            match_ids(collection, ids)
          end

          def self.match_ids(collection, ids)
            primary_key_names = ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(collection)

            raise ForestException, 'Collection must have at least one primary key' if primary_key_names.empty?

            primary_key_names.each do |name|
              operators = collection.fields[name].filter_operators

              unless operators.include?('Equal') || operators.include?('In')
                raise ForestException, "Field '#{name}' must support operators: ['Equal', 'In']"
              end
            end

            match_fields(primary_key_names, ids)
          end

          def self.intersect(trees = nil)
            result = group('And', trees)
            is_empty_and = result.is_a?(ConditionTreeBranch) && result.aggregator == 'And' && result.conditions.empty?

            is_empty_and ? nil : result
          end

          def self.union(trees)
            group('Or', trees)
          end

          def self.from_plain_object(json)
            return nil if json.nil?

            if leaf?(json)
              ConditionTreeLeaf.new(json[:field], json[:operator], json[:value])
            elsif branch?(json)
              branch = ConditionTreeBranch.new(
                json[:aggregator],
                json[:conditions].map { |sub_tree| from_plain_object(sub_tree) }
              )

              branch.conditions.length == 1 ? branch.conditions[0] : branch
            else
              raise ForestException, 'Failed to instantiate condition tree from json'
            end
          end

          def self.group(aggregator, trees = nil)
            conditions = trees
                         .filter { |tree| !tree.nil? }
                         .reduce([]) do |current_conditions, tree|
              if tree.is_a?(ConditionTreeBranch) && tree.aggregator == aggregator
                current_conditions + tree.conditions
              else
                current_conditions + [tree]
              end
            end

            conditions.length == 1 ? conditions[0] : ConditionTreeBranch.new(aggregator, conditions)
          end

          def self.match_fields(fields, values)
            return ConditionTreeFactory.match_none if values.empty?

            if fields.length == 1
              field_values = values.map { |tuple| tuple[0] }

              return field_values.length > 1 ? ConditionTreeLeaf.new(fields[0], 'In', field_values) : ConditionTreeLeaf.new(fields[0], 'Equal', field_values[0])
            end

            first_field, *other_fields = fields
            groups = {}

            values.each do |first_value, *other_values|
              if groups.key?(first_value)
                groups[first_value].push(other_values)
              else
                groups[first_value] = [other_values]
              end
            end

            ConditionTreeFactory.union(
              groups.map do |first_value, sub_values|
                ConditionTreeFactory.intersect([
                                                 ConditionTreeFactory.match_fields([first_field], [[first_value]]),
                                                 ConditionTreeFactory.match_fields(other_fields, sub_values)
                                               ])
              end
            )
          end

          def self.leaf?(tree)
            return false unless tree.is_a?(Hash)

            tree.key?(:field) && tree.key?(:operator) && (tree[:operator] == 'Present' || tree.key?(:value))
          end

          def self.branch?(tree)
            return false unless tree.is_a?(Hash)

            tree.key?(:aggregator) && tree.key?(:conditions)
          end
        end
      end
    end
  end
end
