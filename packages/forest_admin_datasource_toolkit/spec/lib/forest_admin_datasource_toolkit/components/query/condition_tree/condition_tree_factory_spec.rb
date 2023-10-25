require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Query
      module ConditionTree
        include Nodes
        include ForestAdminDatasourceToolkit::Exceptions
        include ForestAdminDatasourceToolkit::Schema
        include ForestAdminDatasourceToolkit::Utils

        describe ConditionTreeFactory do
          subject(:condition_tree_factory) { described_class }

          let(:datasource) { Datasource.new }

          context 'when testing match_records / match_ids' do
            it 'raises an error when the collection has no primary key' do
              collection = Collection.new(datasource, 'cars')
              collection.add_fields({ 'column' => ColumnSchema.new(column_type: 'String') })

              expect do
                condition_tree_factory.match_ids(collection, [[]])
              end.to raise_error(ForestException, '🌳🌳🌳 Collection must have at least one primary key')
            end

            it 'raises an error when the collection does not support equal and in' do
              collection = Collection.new(datasource, 'cars')
              collection.add_fields({ 'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true) })

              expect do
                condition_tree_factory.match_ids(collection, [[]])
              end.to raise_error(ForestException, "🌳🌳🌳 Field 'id' must support operators: ['Equal', 'In']")
            end

            it 'generates matchNone with simple PK' do
              collection = Collection.new(datasource, 'cars')
              collection.add_fields({ 'id' => ColumnSchema.new(
                column_type: 'Number',
                filter_operators: [Operators::EQUAL, Operators::IN],
                is_primary_key: true
              ) })

              expect(condition_tree_factory.match_records(collection, [])).to be_a(ConditionTreeBranch)
              expect(condition_tree_factory.match_records(collection, []).aggregator).to eq('Or')
              expect(condition_tree_factory.match_records(collection, []).conditions).to eq([])
            end

            it 'generates equal with simple PK' do
              collection = Collection.new(datasource, 'cars')
              collection.add_fields({ 'id' => ColumnSchema.new(
                column_type: 'Number',
                filter_operators: [Operators::EQUAL, Operators::IN],
                is_primary_key: true
              ) })

              expect(condition_tree_factory.match_records(collection, [{ 'id' => 1 }])).to be_a(ConditionTreeLeaf)
              expect(condition_tree_factory.match_records(collection, [{ 'id' => 1 }]).field).to eq('id')
              expect(condition_tree_factory.match_records(collection, [{ 'id' => 1 }]).operator).to eq('Equal')
              expect(condition_tree_factory.match_records(collection, [{ 'id' => 1 }]).value).to eq(1)
            end

            it 'generates "In" with simple PK' do
              collection = Collection.new(datasource, 'cars')
              collection.add_fields({ 'id' => ColumnSchema.new(
                column_type: 'Number',
                filter_operators: [Operators::EQUAL, Operators::IN],
                is_primary_key: true
              ) })

              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'id' => 1 }, { 'id' => 2 }])).to be_a(ConditionTreeLeaf)
              expect(condition_tree_factory.match_records(collection, [{ 'id' => 1 }, { 'id' => 2 }]).field).to eq('id')
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'id' => 1 }, { 'id' => 2 }]).operator).to eq('In')
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'id' => 1 }, { 'id' => 2 }]).value).to eq([1, 2])
            end

            it 'generates a simple "And" with a composite PK' do
              collection = Collection.new(datasource, 'cars')
              collection.add_fields(
                {
                  'col1' => ColumnSchema.new(
                    column_type: 'Number',
                    filter_operators: [Operators::EQUAL, Operators::IN],
                    is_primary_key: true
                  ),
                  'col2' => ColumnSchema.new(
                    column_type: 'Number',
                    filter_operators: [Operators::EQUAL, Operators::IN],
                    is_primary_key: true
                  )
                }
              )

              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 }])).to be_a(ConditionTreeBranch)
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 }]).aggregator).to eq('And')
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1,
                                                             'col2' => 1 }]).conditions[0]).to be_a(ConditionTreeLeaf)
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1,
                                                             'col2' => 1 }]).conditions[0].field).to eq('col1')
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1,
                                                             'col2' => 1 }]).conditions[0].operator).to eq('Equal')
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 }]).conditions[0].value).to eq(1)
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1,
                                                             'col2' => 1 }]).conditions[1]).to be_a(ConditionTreeLeaf)
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1,
                                                             'col2' => 1 }]).conditions[1].field).to eq('col2')
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1,
                                                             'col2' => 1 }]).conditions[1].operator).to eq('Equal')
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 }]).conditions[1].value).to eq(1)
            end

            it 'factorizes with a composite PK' do
              collection = Collection.new(datasource, 'cars')
              collection.add_fields(
                {
                  'col1' => ColumnSchema.new(
                    column_type: 'Number',
                    filter_operators: [Operators::EQUAL, Operators::IN],
                    is_primary_key: true
                  ),
                  'col2' => ColumnSchema.new(
                    column_type: 'Number',
                    filter_operators: [Operators::EQUAL, Operators::IN],
                    is_primary_key: true
                  )
                }
              )

              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 1, 'col2' => 2 }])).to be_a(ConditionTreeBranch)
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 1, 'col2' => 2 }]).aggregator).to eq('And')
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 1,
                                                             'col2' => 2 }]).conditions[0]).to be_a(ConditionTreeLeaf)
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 1,
                                                             'col2' => 2 }]).conditions[0].field).to eq('col1')
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 1,
                                                             'col2' => 2 }]).conditions[0].operator).to eq('Equal')
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 1, 'col2' => 2 }]).conditions[0].value).to eq(1)
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 1,
                                                             'col2' => 2 }]).conditions[1]).to be_a(ConditionTreeLeaf)
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 1,
                                                             'col2' => 2 }]).conditions[1].field).to eq('col2')
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 1,
                                                             'col2' => 2 }]).conditions[1].operator).to eq('In')
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 1,
                                                             'col2' => 2 }]).conditions[1].value).to eq([1, 2])
            end

            it 'does not factorize with a composite PK' do
              collection = Collection.new(datasource, 'cars')
              collection.add_fields(
                {
                  'col1' => ColumnSchema.new(
                    column_type: 'Number',
                    filter_operators: [Operators::EQUAL, Operators::IN],
                    is_primary_key: true
                  ),
                  'col2' => ColumnSchema.new(
                    column_type: 'Number',
                    filter_operators: [Operators::EQUAL, Operators::IN],
                    is_primary_key: true
                  )
                }
              )

              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 2, 'col2' => 2 }])).to be_a(ConditionTreeBranch)
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 2, 'col2' => 2 }]).aggregator).to eq('Or')
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 2,
                                                             'col2' => 2 }]).conditions[0]).to be_a(ConditionTreeBranch)
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 2,
                                                             'col2' => 2 }]).conditions[0].aggregator).to eq('And')
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 2,
                                                             'col2' => 2 }]).conditions[0].conditions[0]).to be_a(ConditionTreeLeaf)
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 2,
                                                             'col2' => 2 }]).conditions[0].conditions[0].field).to eq('col1')
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 2,
                                                             'col2' => 2 }]).conditions[0].conditions[0].operator).to eq('Equal')
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 2,
                                                             'col2' => 2 }]).conditions[0].conditions[0].value).to eq(1)
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 2,
                                                             'col2' => 2 }]).conditions[0].conditions[1]).to be_a(ConditionTreeLeaf)
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 2,
                                                             'col2' => 2 }]).conditions[0].conditions[1].field).to eq('col2')
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 2,
                                                             'col2' => 2 }]).conditions[0].conditions[1].operator).to eq('Equal')
              expect(condition_tree_factory.match_records(collection,
                                                          [{ 'col1' => 1, 'col2' => 1 },
                                                           { 'col1' => 2,
                                                             'col2' => 2 }]).conditions[0].conditions[1].value).to eq(1)
            end
          end

          context 'when testing intersect' do
            it 'returns null when called with an empty list' do
              tree = condition_tree_factory.intersect

              expect(tree).to be_nil
            end

            it 'returns the parameter when called with only one param' do
              tree = condition_tree_factory.intersect([ConditionTreeLeaf.new('column', Operators::EQUAL, true)])

              expect(tree).to be_a(ConditionTreeLeaf)
              expect(tree.field).to eq('column')
              expect(tree.operator).to eq(Operators::EQUAL)
              expect(tree.value).to be(true)
            end

            it 'ignores null params' do
              tree = condition_tree_factory.intersect([nil, ConditionTreeLeaf.new('column', Operators::EQUAL, true),
                                                       nil])

              expect(tree).to be_a(ConditionTreeLeaf)
              expect(tree.field).to eq('column')
              expect(tree.operator).to eq(Operators::EQUAL)
              expect(tree.value).to be(true)
            end

            it 'returns multiple trees when receiving multiple trees' do
              condition_tree = ConditionTreeLeaf.new('column', Operators::EQUAL, true)
              other_condition_tree = ConditionTreeLeaf.new('otherColumn', Operators::EQUAL, true)
              tree = condition_tree_factory.intersect([condition_tree, other_condition_tree])

              expect(tree).to be_a(ConditionTreeBranch)
              expect(tree.aggregator).to eq('And')
              expect(tree.conditions).to eq([condition_tree, other_condition_tree])
            end
          end

          context 'when testing from_plain_object' do
            it 'raises an error when calling with badly formatted json' do
              expect do
                condition_tree_factory.from_plain_object('this is not json')
              end.to raise_error('🌳🌳🌳 Failed to instantiate condition tree from json')
            end

            it 'works with a simple case' do
              tree = condition_tree_factory.from_plain_object(
                { field: 'field', operator: 'Equal', value: 'something' }
              )

              expect(tree).to be_a(ConditionTreeLeaf)
              expect(tree.field).to eq('field')
              expect(tree.operator).to eq('Equal')
              expect(tree.value).to eq('something')
            end

            it 'removes useless aggregators from the frontend' do
              tree = condition_tree_factory.from_plain_object(
                { aggregator: 'And', conditions: [{ field: 'field', operator: 'Equal', value: 'something' }] }
              )

              expect(tree).to be_a(ConditionTreeLeaf)
              expect(tree.field).to eq('field')
              expect(tree.operator).to eq('Equal')
              expect(tree.value).to eq('something')
            end

            it 'works with an aggregator' do
              tree = condition_tree_factory.from_plain_object(
                {
                  aggregator: 'And',
                  conditions: [
                    { field: 'field', operator: 'Equal', value: 'something' },
                    { field: 'field', operator: 'Equal', value: 'something' }
                  ]
                }
              )

              expect(tree).to be_a(ConditionTreeBranch)
              expect(tree.aggregator).to eq('And')
              expect(tree.conditions[0]).to be_a(ConditionTreeLeaf)
              expect(tree.conditions[0].field).to eq('field')
              expect(tree.conditions[0].operator).to eq('Equal')
              expect(tree.conditions[0].value).to eq('something')
              expect(tree.conditions[1]).to be_a(ConditionTreeLeaf)
              expect(tree.conditions[1].field).to eq('field')
              expect(tree.conditions[1].operator).to eq('Equal')
              expect(tree.conditions[1].value).to eq('something')
            end
          end
        end
      end
    end
  end
end
