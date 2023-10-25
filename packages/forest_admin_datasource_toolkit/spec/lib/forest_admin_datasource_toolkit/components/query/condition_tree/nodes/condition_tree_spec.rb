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
                expect(@condition_tree_branch.inverse).eql?(
                  ConditionTreeBranch.new('Or', [
                                            ConditionTreeLeaf.new('column1', Operators::NOT_EQUAL, true),
                                            ConditionTreeLeaf.new('column2', Operators::NOT_EQUAL, true)
                                          ])
                )
                expect(@condition_tree_branch.inverse.inverse).eql?(@condition_tree_branch)
              end

              it 'works with blank' do
                condition_tree_leaf = ConditionTreeLeaf.new('column1', Operators::BLANK)
                expect(condition_tree_leaf.inverse).eql?(
                  ConditionTreeLeaf.new('column1', Operators::PRESENT)
                )
                expect(condition_tree_leaf.inverse.inverse).eql?(condition_tree_leaf)
              end

              it 'crashes with unsupported operator' do
                condition_tree_leaf = ConditionTreeLeaf.new('column1', Operators::TODAY)
                expect do
                  condition_tree_leaf.inverse
                end.to raise_error(ForestException, '🌳🌳🌳 Operator: Today cannot be inverted.')
              end
            end

            it 'when calling replace_leafs should work' do
              expect(@condition_tree_branch.replace_leafs { |leaf| leaf.override(value: !leaf.value) }).eql?(
                ConditionTreeBranch.new('And', [
                                          ConditionTreeLeaf.new('column1', Operators::EQUAL, false),
                                          ConditionTreeLeaf.new('column2', Operators::EQUAL, false)
                                        ])
              )
            end

            it 'when calling for_each_leaf should work' do
              expect(@condition_tree_branch.for_each_leaf { |leaf| leaf.override(field: 'field') }).eql?(
                ConditionTreeBranch.new('And', [
                                          ConditionTreeLeaf.new('field', Operators::EQUAL, true),
                                          ConditionTreeLeaf.new('field', Operators::EQUAL, true)
                                        ])
              )
            end

            it 'when calling some_leaf should work' do
              expect(@condition_tree_branch.some_leaf { |leaf| leaf.value == true }).to be_truthy
              expect(@condition_tree_branch.some_leaf { |leaf| leaf.field == 'column1' }).to be_truthy
              expect(@condition_tree_branch.some_leaf { |leaf| leaf.field.start_with?('something') }).to be_falsey
            end

            it 'when calling projection should work' do
              expect(@condition_tree_branch.projection).to eq(Projection.new(['column1', 'column2']))
            end

            it 'when calling apply should work' do
              collection = Collection.new(Datasource.new, 'myCollection')
              collection.add_fields(
                {
                  'column1' => ColumnSchema.new(
                    column_type: 'Boolean',
                    filter_operators: [Operators::EQUAL]
                  ),
                  'column2' => ColumnSchema.new(
                    column_type: 'Boolean',
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
              expect(@condition_tree_branch.nest('prefix')).eql?(
                ConditionTreeBranch.new('And', [
                                          ConditionTreeLeaf.new('prefix:column1', Operators::EQUAL, true),
                                          ConditionTreeLeaf.new('prefix:column2', Operators::EQUAL, true)
                                        ])
              )
            end

            context 'when calling unnest' do
              it 'works with conditionTreeBranch' do
                expect(@condition_tree_branch.nest('prefix').unnest).eql?(@condition_tree_branch)
              end

              it 'works with conditionTreeLeaf' do
                @condition_tree_branch = @condition_tree_branch.nest('prefix')
                condition_tree_leaf = @condition_tree_branch.conditions[0]
                expect(condition_tree_leaf.unnest).eql?(ConditionTreeLeaf.new('column1', Operators::EQUAL, true))
              end

              it 'throws' do
                expect do
                  @condition_tree_branch.unnest
                end.to raise_error(ForestException, '🌳🌳🌳 Cannot unnest condition tree.')
              end
            end

            it 'when calling replace_fields should work' do
              expect(@condition_tree_branch.replace_fields { |field| "#{field}:suffix" }).eql?(
                ConditionTreeBranch.new('And', [
                                          ConditionTreeLeaf.new('column1:suffix', Operators::EQUAL, true),
                                          ConditionTreeLeaf.new('column2:suffix', Operators::EQUAL, true)
                                        ])
              )
            end
          end
        end
      end
    end
  end
end
