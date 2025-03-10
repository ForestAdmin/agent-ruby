require 'spec_helper'

module ForestAdminDatasourceMongoid
  module Utils
    module Pipeline
      include ForestAdminDatasourceToolkit::Components::Query
      describe FilterGenerator do
        before do
          logger = instance_double(Logger, log: nil)
          allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
        end

        let(:datasource) { ForestAdminDatasourceMongoid::Datasource.new(options: { flatten_mode: 'auto' }) }
        let(:model) { datasource.get_collection('Post').model }
        let(:stack) { [{ prefix: nil, as_fields: [], as_models: [] }] }

        describe '.filter' do
          describe 'Condition tree' do
            it 'filter should generate a $match stage' do
              filter = Filter.new(
                condition_tree: ConditionTree::Nodes::ConditionTreeLeaf.new('title', 'Match', /^Foundation$/i)
              )
              pipeline = described_class.filter(model, stack, filter)
              expect(pipeline).to eq([{ '$match' => { 'title' => { '$regex' => /^Foundation$/i } } }])
            end

            it 'filter should generate a $addFields and $match stage' do
              filter = Filter.new(
                condition_tree: ConditionTree::Nodes::ConditionTreeLeaf.new('author:id', 'NotContains', 'something')
              )
              comment = datasource.get_collection('Comment').model
              pipeline = described_class.filter(comment, stack, filter)
              expect(pipeline).to eq([
                                       { '$match' => { 'author.id' => { '$not' => /^.*something.*$/ } } }
                                     ])
            end

            it 'filter should generate a $match stage with $and and $or nodes' do
              filter = Filter.new(
                condition_tree: ConditionTree::Nodes::ConditionTreeBranch.new('And', [
                                                                                ConditionTree::Nodes::ConditionTreeLeaf.new('author:lastname', 'Equal', 'Asimov'),
                                                                                ConditionTree::Nodes::ConditionTreeBranch.new('Or', [
                                                                                                                                ConditionTree::Nodes::ConditionTreeLeaf.new('author:firstname', 'Equal', 'Isaac'),
                                                                                                                                ConditionTree::Nodes::ConditionTreeLeaf.new('author:firstname', 'Equal', 'John')
                                                                                                                              ])
                                                                              ])
              )
              pipeline = described_class.filter(model, stack, filter)
              expect(pipeline).to eq([
                                       {
                                         '$match' => {
                                           '$and' => [
                                             { 'author.lastname' => { '$eq' => 'Asimov' } },
                                             {
                                               '$or' => [
                                                 { 'author.firstname' => { '$eq' => 'Isaac' } },
                                                 { 'author.firstname' => { '$eq' => 'John' } }
                                               ]
                                             }
                                           ]
                                         }
                                       }
                                     ])
            end
          end

          describe 'Skip & Limit' do
            it 'generates the relevant pipeline' do
              filter = Filter.new(page: Page.new(offset: 100, limit: 150))
              pipeline = described_class.sort_and_paginate(model, filter)
              expect(pipeline).to eq([[{ '$skip' => 100 }, { '$limit' => 150 }], [], []])
            end
          end

          describe 'Sort' do
            context 'when sort is done on native field' do
              it 'generates the relevant pipeline on the first stage' do
                filter = Filter.new(sort: Sort.new([{ field: 'author:first_name', ascending: true }]))
                pipeline = described_class.sort_and_paginate(model, filter)
                expect(pipeline).to eq([[], [], [{ '$sort' => { 'author.first_name' => 1 } }]])
              end
            end

            context 'when filtering is applied' do
              context 'with filtering is on a native field' do
                it 'generates the relevant pipeline on first stage' do
                  filter = Filter.new(
                    sort: Sort.new([{ field: 'title', ascending: true }]),
                    condition_tree: ConditionTree::Nodes::ConditionTreeLeaf.new('title', 'Equal', 'Lord of the Rings')
                  )
                  pipeline = described_class.sort_and_paginate(model, filter)
                  expect(pipeline).to eq([[], [{ '$sort' => { 'title' => 1 } }], []])
                end
              end

              context 'with filtering is not on a native field' do
                it 'generates the relevant pipeline on third stage' do
                  filter = Filter.new(
                    sort: Sort.new([{ field: 'author:first_name', ascending: true }]),
                    condition_tree: ConditionTree::Nodes::ConditionTreeLeaf.new('editor', 'Equal', 'Folio')
                  )
                  pipeline = described_class.sort_and_paginate(model, filter)
                  expect(pipeline).to eq([[], [], [{ '$sort' => { 'author.first_name' => 1 } }]])
                end
              end
            end

            context 'when sort criteria is not on a native field' do
              it 'generates the relevant pipeline on second stage' do
                filter = Filter.new(sort: Sort.new([{ field: 'hello', ascending: true }]))
                pipeline = described_class.sort_and_paginate(model, filter)
                expect(pipeline).to eq([[], [], [{ '$sort' => { 'hello' => 1 } }]])
              end
            end
          end
        end

        describe '.list_relations_used_in_filter' do
          context 'with sort' do
            it 'adds relations used to sort' do
              filter = Filter.new(sort: Sort.new([{ field: 'author:first_name', ascending: true }, { field: 'editor:name', ascending: false }]))
              fields = described_class.list_relations_used_in_filter(filter)
              expect(fields).to eq(['author', 'editor'])
            end

            it 'does not add anything if soting is done on direct fields' do
              filter = Filter.new(sort: Sort.new([{ field: 'title', ascending: true }]))
              fields = described_class.list_relations_used_in_filter(filter)
              expect(fields).to eq([])
            end

            it 'does not add anything if sort is undefined' do
              filter = Filter.new
              fields = described_class.list_relations_used_in_filter(filter)
              expect(fields).to eq([])
            end

            it 'adds all parents and correctly format nested fields' do
              filter = Filter.new(sort: Sort.new([{ field: 'author:country:name', ascending: true }]))
              fields = described_class.list_relations_used_in_filter(filter)
              expect(fields).to eq(['author', 'author.country'])
            end
          end
        end
      end
    end
  end
end
