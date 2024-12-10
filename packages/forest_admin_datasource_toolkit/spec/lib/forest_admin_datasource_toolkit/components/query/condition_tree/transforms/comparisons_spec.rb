require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Query
      module ConditionTree
        module Transforms
          include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes

          describe Comparisons do
            subject(:comparisons) { described_class }

            before do
              @comparisons = comparisons.transforms
            end

            it 'rewrites blank for strings' do
              expect(@comparisons[Operators::BLANK][0][:replacer].call(ConditionTreeLeaf.new('column',
                                                                                             Operators::BLANK)))
                .to eq(ConditionTreeLeaf.new('column', Operators::IN, [nil, '']))
            end

            it 'rewrites blank for other types' do
              expect(@comparisons[Operators::BLANK][1][:replacer].call(ConditionTreeLeaf.new('column',
                                                                                             Operators::BLANK)))
                .to eq(ConditionTreeLeaf.new('column', Operators::MISSING))
            end

            it 'missing should be rewritten' do
              expect(@comparisons[Operators::MISSING][0][:replacer].call(ConditionTreeLeaf.new('column',
                                                                                               Operators::MISSING)))
                .to eq(ConditionTreeLeaf.new('column', Operators::EQUAL, nil))
            end

            it 'Present should be rewritten for strings' do
              expect(@comparisons[Operators::PRESENT][0][:replacer].call(ConditionTreeLeaf.new('column',
                                                                                               Operators::PRESENT)))
                .to eq(ConditionTreeLeaf.new('column', Operators::NOT_IN, [nil, '']))
            end

            it 'Present should be rewritten for other types' do
              expect(@comparisons[Operators::PRESENT][1][:replacer].call(ConditionTreeLeaf.new('column',
                                                                                               Operators::PRESENT)))
                .to eq(ConditionTreeLeaf.new('column', Operators::NOT_EQUAL, nil))
            end

            it 'Equal should be rewritten' do
              expect(@comparisons[Operators::EQUAL][0][:replacer].call(ConditionTreeLeaf.new('column',
                                                                                             Operators::EQUAL, 'something')))
                .to eq(ConditionTreeLeaf.new('column', Operators::IN, ['something']))
            end

            it 'In should be rewritten with one element' do
              expect(@comparisons[Operators::IN][0][:replacer].call(ConditionTreeLeaf.new('column', Operators::IN,
                                                                                          ['something', 'else'])))
                .to eq(ConditionTreeLeaf.new('column', Operators::MATCH, '/(something|else)/g'))
            end

            it 'In should be rewritten with multiple elements' do
              expect(@comparisons[Operators::IN][0][:replacer].call(ConditionTreeLeaf.new('column', Operators::IN,
                                                                                          [nil, 'something', 'else'])))
                .to eq(ConditionTreeBranch.new('Or', [
                                                 ConditionTreeLeaf.new('column', Operators::EQUAL, nil),
                                                 ConditionTreeLeaf.new('column', Operators::MATCH, '/(something|else)/g')
                                               ]))
            end

            it 'NotEqual should be rewritten' do
              expect(@comparisons[Operators::NOT_EQUAL][0][:replacer].call(ConditionTreeLeaf.new('column',
                                                                                                 Operators::NOT_EQUAL, 'something')))
                .to eq(ConditionTreeLeaf.new('column', Operators::NOT_IN, ['something']))
            end

            it 'NotIn should be rewritten with one element' do
              expect(@comparisons[Operators::NOT_IN][0][:replacer].call(ConditionTreeLeaf.new('column',
                                                                                              Operators::NOT_IN, ['something'])))
                .to eq(ConditionTreeLeaf.new('column', Operators::MATCH, '/(?!something)/g'))
            end

            it 'NotIn should be rewritten with multiple elements' do
              expect(@comparisons[Operators::NOT_IN][0][:replacer].call(ConditionTreeLeaf.new('column',
                                                                                              Operators::NOT_IN, ['something', 'else'])))
                .to eq(ConditionTreeLeaf.new('column', Operators::MATCH, '/(?!something|else)/g'))
            end
          end
        end
      end
    end
  end
end
