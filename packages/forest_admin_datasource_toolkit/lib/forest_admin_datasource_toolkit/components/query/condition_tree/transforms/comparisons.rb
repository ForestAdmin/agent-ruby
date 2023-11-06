module ForestAdminDatasourceToolkit
  module Components
    module Query
      module ConditionTree
        module Transforms
          class Comparisons
            include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes

            def self.transforms
              {
                Operators::BLANK => [
                  {
                    depends_on: [Operators::IN],
                    for_types: ['String'],
                    replacer: ->(leaf) { leaf.override({ operator: Operators::IN, value: [nil, ''] }) }
                  },
                  {
                    depends_on: [Operators::MISSING],
                    replacer: ->(leaf) { leaf.override({ operator: Operators::MISSING }) }
                  }
                ],
                Operators::MISSING => [
                  {
                    depends_on: [Operators::EQUAL],
                    replacer: ->(leaf) { leaf.override({ operator: Operators::EQUAL, value: nil }) }
                  }
                ],
                Operators::PRESENT => [
                  {
                    depends_on: [Operators::NOT_IN],
                    for_types: ['String'],
                    replacer: ->(leaf) { leaf.override({ operator: Operators::NOT_IN, value: [nil, ''] }) }
                  },
                  {
                    depends_on: [Operators::NOT_EQUAL],
                    replacer: ->(leaf) { leaf.override({ operator: Operators::NOT_EQUAL, value: nil }) }
                  }
                ],
                Operators::EQUAL => [
                  {
                    depends_on: [Operators::IN],
                    replacer: ->(leaf) { leaf.override({ operator: Operators::IN, value: [leaf.value] }) }
                  }
                ],
                Operators::IN => [
                  {
                    depends_on: [Operators::EQUAL, Operators::MATCH],
                    for_types: ['String'],
                    replacer: lambda { |leaf|
                      values = leaf.value
                      conditions = []

                      [nil, ''].each do |value|
                        if values.include?(value)
                          conditions.push(ConditionTreeLeaf.new(leaf.field, Operators::EQUAL, value))
                        end
                      end

                      if values.any? { |value| !value.nil? && value != '' }
                        escaped = values.filter { |value| !value.nil? && value != '' }

                        conditions.push(ConditionTreeLeaf.new(leaf.field, Operators::MATCH,
                                                              "/(#{escaped.join("|")})/g"))
                      end

                      ConditionTreeFactory.union(conditions)
                    }
                  },
                  {
                    depends_on: [Operators::EQUAL],
                    replacer: lambda { |leaf|
                      ConditionTreeFactory.union(
                        leaf.value.map { |item| leaf.override({ operator: Operators::EQUAL, value: item }) }
                      )
                    }
                  }
                ],
                Operators::NOT_EQUAL => [
                  {
                    depends_on: [Operators::NOT_IN],
                    replacer: ->(leaf) { leaf.override({ operator: Operators::NOT_IN, value: [leaf.value] }) }
                  }
                ],
                Operators::NOT_IN => [
                  {
                    depends_on: [Operators::NOT_EQUAL, Operators::MATCH],
                    for_types: ['String'],
                    replacer: lambda { |leaf|
                      values = leaf.value
                      conditions = []

                      [nil, ''].each do |value|
                        if values.include?(value)
                          conditions.push(ConditionTreeLeaf.new(leaf.field, Operators::NOT_EQUAL, value))
                        end
                      end

                      if values.any? { |value| !value.nil? && value != '' }
                        escaped = values.filter { |value| !value.nil? && value != '' }
                        conditions.push(ConditionTreeLeaf.new(leaf.field, Operators::MATCH,
                                                              "/(?!(#{escaped.join("|")}))/g"))
                      end

                      ConditionTreeFactory.intersect(conditions)
                    }
                  },
                  {
                    depends_on: [Operators::NOT_EQUAL],
                    replacer: lambda { |leaf|
                      ConditionTreeFactory.intersect(
                        leaf.value.map { |item| leaf.override({ operator: Operators::NOT_EQUAL, value: item }) }
                      )
                    }
                  }
                ]
              }
            end
          end
        end
      end
    end
  end
end
