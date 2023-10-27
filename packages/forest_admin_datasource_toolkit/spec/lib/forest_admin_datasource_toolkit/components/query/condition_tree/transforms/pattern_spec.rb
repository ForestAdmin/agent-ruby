require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Query
      module ConditionTree
        module Transforms
          include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes

          describe Pattern do
            subject(:pattern) { described_class }

            before do
              @pattern = pattern.transforms
            end

            it 'Contains should be rewritten' do
              expect(@pattern[Operators::CONTAINS][0][:replacer].call(ConditionTreeLeaf.new('column',
                                                                                            Operators::CONTAINS, 'something')))
                .eql?(ConditionTreeLeaf.new('column', Operators::LIKE, '%something%'))
            end

            it 'StartsWith should be rewritten' do
              expect(@pattern[Operators::STARTS_WITH][0][:replacer].call(ConditionTreeLeaf.new('column',
                                                                                               Operators::STARTS_WITH, 'something')))
                .eql?(ConditionTreeLeaf.new('column', Operators::LIKE, 'something%'))
            end

            it 'EndsWith should be rewritten' do
              expect(@pattern[Operators::ENDS_WITH][0][:replacer].call(ConditionTreeLeaf.new('column',
                                                                                             Operators::ENDS_WITH, 'something')))
                .eql?(ConditionTreeLeaf.new('column', Operators::LIKE, '%something'))
            end

            it 'I_Contains should be rewritten' do
              expect(@pattern[Operators::I_CONTAINS][0][:replacer].call(ConditionTreeLeaf.new('column',
                                                                                              Operators::CONTAINS, 'something')))
                .eql?(ConditionTreeLeaf.new('column', Operators::I_LIKE, '%something%'))
            end

            it 'IStartsWith should be rewritten' do
              expect(@pattern[Operators::I_STARTS_WITH][0][:replacer].call(ConditionTreeLeaf.new('column',
                                                                                                 Operators::STARTS_WITH, 'something')))
                .eql?(ConditionTreeLeaf.new('column', Operators::I_LIKE, 'something%'))
            end

            it 'IEndsWith should be rewritten' do
              expect(@pattern[Operators::I_ENDS_WITH][0][:replacer].call(ConditionTreeLeaf.new('column',
                                                                                               Operators::ENDS_WITH, 'something')))
                .eql?(ConditionTreeLeaf.new('column', Operators::I_LIKE, '%something'))
            end

            it 'Like should be rewritten' do
              expect(@pattern[Operators::LIKE][0][:replacer].call(ConditionTreeLeaf.new('column', Operators::EQUAL,
                                                                                        'something')))
                .eql?(ConditionTreeLeaf.new('column', Operators::MATCH, '/^something$/'))
            end

            it 'ILike should be rewritten' do
              expect(@pattern[Operators::I_LIKE][0][:replacer].call(ConditionTreeLeaf.new('column', Operators::EQUAL,
                                                                                          'something')))
                .eql?(ConditionTreeLeaf.new('column', Operators::MATCH, '/^something$/i'))
            end
          end
        end
      end
    end
  end
end
