require 'spec_helper'

module ForestAdminDatasourceMongoid
  module Utils
    include ForestAdminDatasourceToolkit::Components::Query
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes
    describe Query do
      let(:datasource) { ForestAdminDatasourceMongoid::Datasource.new }
      let(:collection) { datasource.get_collection('Post') }

      describe 'apply sort' do
        it 'add sort clauses to the query' do
          sort = Sort.new([{ field: 'title', ascending: true }, { field: 'body', ascending: false }])
          filter = Filter.new(sort: sort)
          query_builder = described_class.new(collection, Projection.new, filter)
          query_builder.build

          expect(query_builder.query.options).to eq({ sort: { 'body' => -1, 'title' => 1 } })
        end
      end

      describe 'apply pagination' do
        it 'add pagination clause to the query' do
          page = Page.new(offset: 10, limit: 20)
          filter = Filter.new(page: page)
          query_builder = described_class.new(collection, Projection.new, filter)
          query = query_builder.get

          expect(query.options).to eq({ skip: 10, limit: 20 })
        end

        it 'do not add limitation clause to the query if pagination is missing' do
          query_builder = described_class.new(collection, Projection.new, Filter.new)
          query = query_builder.get

          expect(query.options).to eq({})
        end
      end

      describe 'apply projection' do
        it 'add projection to the query' do
          projection = Projection.new(%w[_id title body])
          query_builder = described_class.new(collection, projection, Filter.new)
          query_builder.build

          expect(query_builder.query.options).to eq({ fields: { '_id' => 1, 'title' => 1, 'body' => 1 } })
        end
      end

      describe 'apply condition tree' do
        context 'with simple condition tree' do
          it 'add present condition' do
            filter = Filter.new(
              condition_tree: ConditionTreeLeaf.new('title', Operators::PRESENT)
            )
            query_builder = described_class.new(collection, Projection.new, filter)
            query_builder.build

            expect(query_builder.query.selector).to eq({ 'title' => { '$ne' => nil } })
          end

          it 'add equal condition' do
            filter = Filter.new(
              condition_tree: ConditionTreeLeaf.new('title', Operators::EQUAL, 'foo')
            )
            query_builder = described_class.new(collection, Projection.new, filter)
            query_builder.build

            expect(query_builder.query.selector).to eq({ 'title' => 'foo' })
          end

          it 'add in condition' do
            filter = Filter.new(
              condition_tree: ConditionTreeLeaf.new('title', Operators::IN, 'foo')
            )
            query_builder = described_class.new(collection, Projection.new, filter)
            query_builder.build

            expect(query_builder.query.selector).to eq({ 'title' => { '$in' => ['foo'] } })
          end

          it 'add not_equal condition' do
            filter = Filter.new(
              condition_tree: ConditionTreeLeaf.new('title', Operators::NOT_EQUAL, 'foo')
            )
            query_builder = described_class.new(collection, Projection.new, filter)
            query_builder.build

            expect(query_builder.query.selector).to eq({ 'title' => { '$ne' => 'foo' } })
          end

          it 'add not_in condition' do
            filter = Filter.new(
              condition_tree: ConditionTreeLeaf.new('title', Operators::NOT_IN, 'foo')
            )
            query_builder = described_class.new(collection, Projection.new, filter)
            query_builder.build

            expect(query_builder.query.selector).to eq({ 'title' => { '$not' => { '$in' => ['foo'] } } })
          end

          it 'add greater_than condition' do
            filter = Filter.new(
              condition_tree: ConditionTreeLeaf.new('title', Operators::GREATER_THAN, 1)
            )
            query_builder = described_class.new(collection, Projection.new, filter)
            query_builder.build

            expect(query_builder.query.selector).to eq({ 'title' => { '$gt' => '1' } })
          end

          it 'add less_than condition' do
            filter = Filter.new(
              condition_tree: ConditionTreeLeaf.new('title', Operators::LESS_THAN, 1)
            )
            query_builder = described_class.new(collection, Projection.new, filter)
            query_builder.build

            expect(query_builder.query.selector).to eq({ 'title' => { '$lt' => '1' } })
          end

          it 'add not_contains condition' do
            filter = Filter.new(
              condition_tree: ConditionTreeLeaf.new('title', Operators::NOT_CONTAINS, 'foo')
            )
            query_builder = described_class.new(collection, Projection.new, filter)
            query_builder.build

            expect(query_builder.query.selector).to eq({ 'title' => { '$not' => /^.*foo.*$/ } })
          end

          it 'add not_i_contains condition' do
            filter = Filter.new(
              condition_tree: ConditionTreeLeaf.new('title', Operators::NOT_I_CONTAINS, 'foo')
            )
            query_builder = described_class.new(collection, Projection.new, filter)
            query_builder.build

            expect(query_builder.query.selector).to eq({ 'title' => { '$not' => /^.*foo.*$/i } })
          end

          it 'add match condition' do
            filter = Filter.new(
              condition_tree: ConditionTreeLeaf.new('title', Operators::MATCH, 'foo')
            )
            query_builder = described_class.new(collection, Projection.new, filter)
            query_builder.build

            expect(query_builder.query.selector).to eq({ 'title' => { '$regex' => 'foo' } })
          end
        end

        context 'with condition tree branch' do
          it 'add condition with "and" aggregator' do
            filter = Filter.new(
              condition_tree: ConditionTreeBranch.new(
                'and',
                [
                  ConditionTreeLeaf.new('title', Operators::PRESENT),
                  ConditionTreeLeaf.new('body', Operators::PRESENT)
                ]
              )
            )
            query_builder = described_class.new(collection, Projection.new, filter)
            query_builder.build

            expect(query_builder.query.selector).to eq(
              { 'body' => { '$ne' => nil }, 'title' => { '$ne' => nil } }
            )
          end

          it 'add condition with "or" aggregator' do
            filter = Filter.new(
              condition_tree: ConditionTreeBranch.new(
                'or',
                [
                  ConditionTreeLeaf.new('title', Operators::PRESENT),
                  ConditionTreeLeaf.new('body', Operators::PRESENT)
                ]
              )
            )
            query_builder = described_class.new(collection, Projection.new, filter)
            query_builder.build

            expect(query_builder.query.selector).to eq(
              { '$or' => [{ 'title' => { '$ne' => nil } }, { 'body' => { '$ne' => nil } }] }
            )
          end

          it 'add condition with nested condition tree branch' do
            filter = Filter.new(
              condition_tree: ConditionTreeBranch.new(
                'and',
                [
                  ConditionTreeBranch.new(
                    'or',
                    [
                      ConditionTreeLeaf.new('title', Operators::PRESENT),
                      ConditionTreeLeaf.new('body', Operators::PRESENT)
                    ]
                  ),
                  ConditionTreeLeaf.new('title', Operators::PRESENT),
                  ConditionTreeLeaf.new('body', Operators::PRESENT)
                ]
              )
            )
            query_builder = described_class.new(collection, Projection.new, filter)
            query_builder.build

            expect(query_builder.query.selector).to eq(
              { '$or' => [{ 'title' => { '$ne' => nil } }, { 'body' => { '$ne' => nil } }], 'body' => { '$ne' => nil }, 'title' => { '$ne' => nil } }
            )
          end
        end
      end
    end
  end
end
