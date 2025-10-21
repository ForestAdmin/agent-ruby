require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Query
      module ConditionTree
        module Nodes
          include ForestAdminDatasourceToolkit::Exceptions
          include ForestAdminDatasourceToolkit::Schema

          describe ConditionTree do
            before do
              @condition_tree_branch = ConditionTreeBranch.new('And', [
                                                                 ConditionTreeLeaf.new('column1', Operators::EQUAL,
                                                                                       true),
                                                                 ConditionTreeLeaf.new('column2', Operators::EQUAL,
                                                                                       true)
                                                               ])
            end

            context 'when calling inverse method' do
              it 'works with not_equal' do
                expect(@condition_tree_branch.inverse).to have_attributes(
                  aggregator: 'Or',
                  conditions: contain_exactly(
                    have_attributes(field: 'column1', operator: Operators::NOT_EQUAL, value: true),
                    have_attributes(field: 'column2', operator: Operators::NOT_EQUAL, value: true)
                  )
                )
                expect(@condition_tree_branch.inverse.inverse.to_h).to eq(@condition_tree_branch.to_h)
              end

              it 'works with blank' do
                condition_tree_leaf = ConditionTreeLeaf.new('column1', Operators::BLANK)
                expect(condition_tree_leaf.inverse.to_h).to eq(
                  ConditionTreeLeaf.new('column1', Operators::PRESENT).to_h
                )
                expect(condition_tree_leaf.inverse.inverse.to_h).to eq(ConditionTreeLeaf.new('column1', Operators::BLANK).to_h)
              end

              it 'crashes with unsupported operator' do
                condition_tree_leaf = ConditionTreeLeaf.new('column1', Operators::TODAY)
                expect do
                  condition_tree_leaf.inverse
                end.to raise_error(ForestException, 'Operator: today cannot be inverted.')
              end
            end

            it 'when calling replace_leafs should work' do
              expect(@condition_tree_branch.replace_leafs { |leaf| leaf.override(value: !leaf.value) }.to_h).to eq(
                ConditionTreeBranch.new('And', [
                                          ConditionTreeLeaf.new('column1', Operators::EQUAL, false),
                                          ConditionTreeLeaf.new('column2', Operators::EQUAL, false)
                                        ]).to_h
              )
            end

            context 'when calling match' do
              it 'works with many fields' do
                collection = Collection.new(Datasource.new, 'myCollection')
                collection.add_fields(
                  {
                    'column1' => ColumnSchema.new(
                      column_type: PrimitiveType::BOOLEAN,
                      filter_operators: [Operators::EQUAL]
                    ),
                    'column2' => ColumnSchema.new(
                      column_type: PrimitiveType::BOOLEAN,
                      filter_operators: [Operators::EQUAL]
                    )
                  }
                )
                expect(@condition_tree_branch.match({ 'column1' => true, 'column2' => true }, collection,
                                                    'Europe/Paris')).to be_truthy
                expect(@condition_tree_branch.match({ 'column1' => true, 'column2' => false }, collection,
                                                    'Europe/Paris')).to be_falsey
                expect(@condition_tree_branch.inverse.match({ 'column1' => true, 'column2' => true }, collection,
                                                            'Europe/Paris')).to be_falsey
                expect(@condition_tree_branch.inverse.match({ 'column1' => true, 'column2' => false }, collection,
                                                            'Europe/Paris')).to be_truthy
              end

              it 'works with many operators' do
                collection = Collection.new(Datasource.new, 'myCollection')
                collection.add_fields(
                  {
                    'string' => ColumnSchema.new(
                      column_type: PrimitiveType::STRING,
                      filter_operators: [Operators::EQUAL]
                    ),
                    'array' => ColumnSchema.new(
                      column_type: [PrimitiveType::STRING],
                      filter_operators: [Operators::EQUAL]
                    )
                  }
                )

                all_conditions = ConditionTreeBranch.new('And', [
                                                           ConditionTreeLeaf.new('string', Operators::PRESENT),
                                                           ConditionTreeLeaf.new('string', Operators::MATCH,
                                                                                 '/value/'),
                                                           ConditionTreeLeaf.new('string', Operators::LESS_THAN,
                                                                                 'valuf'),
                                                           ConditionTreeLeaf.new('string', Operators::EQUAL, 'value'),
                                                           ConditionTreeLeaf.new('string', Operators::GREATER_THAN,
                                                                                 'valud'),
                                                           ConditionTreeLeaf.new('string', Operators::IN, ['value']),
                                                           ConditionTreeLeaf.new('array', Operators::INCLUDES_ALL,
                                                                                 ['value']),
                                                           ConditionTreeLeaf.new('string', Operators::LONGER_THAN, 0),
                                                           ConditionTreeLeaf.new('string', Operators::SHORTER_THAN,
                                                                                 999),
                                                           ConditionTreeLeaf.new('string', Operators::STARTS_WITH,
                                                                                 'val'),
                                                           ConditionTreeLeaf.new('string', Operators::ENDS_WITH,
                                                                                 'lue')
                                                         ])

                expect(all_conditions.match({ 'string' => 'value', 'array' => ['value'] }, collection,
                                            'Europe/Paris')).to be_truthy
              end

              it 'works with null value' do
                collection = Collection.new(Datasource.new, 'myCollection')
                collection.add_fields(
                  {
                    'string' => ColumnSchema.new(
                      column_type: PrimitiveType::STRING,
                      filter_operators: [Operators::EQUAL]
                    )
                  }
                )
                leaf = ConditionTreeLeaf.new('string', Operators::MATCH, '%value%')

                expect(leaf.match({ 'string' => nil }, collection, 'Europe/Paris')).to be_falsey
              end
            end

            it 'when calling for_each_leaf should work' do
              expect(@condition_tree_branch.for_each_leaf { |leaf| leaf.override(field: 'field') }.to_h).to eq(
                ConditionTreeBranch.new('And', [
                                          ConditionTreeLeaf.new('field', Operators::EQUAL, true),
                                          ConditionTreeLeaf.new('field', Operators::EQUAL, true)
                                        ]).to_h
              )
            end

            it 'when calling some_leaf should work' do
              expect(@condition_tree_branch.some_leaf { |leaf| leaf.value == true }).to be_truthy
              expect(@condition_tree_branch.some_leaf { |leaf| leaf.field == 'column1' }).to be_truthy
              expect(@condition_tree_branch.some_leaf { |leaf| leaf.field.start_with?('something') }).to be_falsey
            end

            it 'when calling projection should work' do
              expect(@condition_tree_branch.projection).to include('column1', 'column2')
            end

            it 'when calling apply should work' do
              collection = Collection.new(Datasource.new, 'myCollection')
              collection.add_fields(
                {
                  'column1' => ColumnSchema.new(
                    column_type: PrimitiveType::BOOLEAN,
                    filter_operators: [Operators::EQUAL]
                  ),
                  'column2' => ColumnSchema.new(
                    column_type: PrimitiveType::BOOLEAN,
                    filter_operators: [Operators::EQUAL]
                  )
                }
              )
              records = [
                { 'id' => 1, 'column1' => true, 'column2' => true },
                { 'id' => 2, 'column1' => false, 'column2' => true },
                { 'id' => 3, 'column1' => true, 'column2' => false }
              ]
              expect(@condition_tree_branch.apply(records, collection, 'Europe/Paris')).to eq(
                [
                  { 'id' => 1, 'column1' => true, 'column2' => true }
                ]
              )
            end

            it 'when calling nest should work' do
              expect(@condition_tree_branch.nest('prefix').to_h).to eq(
                ConditionTreeBranch.new('And', [
                                          ConditionTreeLeaf.new('prefix:column1', Operators::EQUAL, true),
                                          ConditionTreeLeaf.new('prefix:column2', Operators::EQUAL, true)
                                        ]).to_h
              )
            end

            context 'when calling unnest' do
              it 'works with conditionTreeBranch' do
                expect(@condition_tree_branch.nest('prefix').unnest.to_h).to eq(@condition_tree_branch.to_h)
              end

              it 'works with conditionTreeLeaf' do
                @condition_tree_branch = @condition_tree_branch.nest('prefix')
                condition_tree_leaf = @condition_tree_branch.conditions[0]
                expect(condition_tree_leaf.unnest.to_h).to eq(ConditionTreeLeaf.new('column1', Operators::EQUAL, true).to_h)
              end

              it 'throws' do
                expect do
                  @condition_tree_branch.unnest
                end.to raise_error(ForestException, 'Cannot unnest condition tree.')
              end
            end

            it 'when calling replace_fields should work' do
              expect(@condition_tree_branch.replace_fields { |field| "#{field}:suffix" }.to_h).to eq(
                ConditionTreeBranch.new('And', [
                                          ConditionTreeLeaf.new('column1:suffix', Operators::EQUAL, true),
                                          ConditionTreeLeaf.new('column2:suffix', Operators::EQUAL, true)
                                        ]).to_h
              )
            end
          end
        end
      end
    end
  end
end
