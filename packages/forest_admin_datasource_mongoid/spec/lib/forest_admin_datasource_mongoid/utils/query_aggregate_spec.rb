require 'spec_helper'

module ForestAdminDatasourceMongoid
  module Utils
    include ForestAdminDatasourceToolkit::Components::Query
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes
    describe QueryAggregate do
      let(:datasource) { ForestAdminDatasourceMongoid::Datasource.new }
      let(:collection) { datasource.get_collection('Post') }

      describe 'apply limit' do
        it 'add limit clauses to the query' do
          aggregation = Aggregation.new(operation: 'Count')
          query_aggregate = described_class.new(collection, aggregation, Filter.new, 10)
          query_aggregate.get

          expect(query_aggregate.query.options).to eq({ limit: 10 })
        end
      end

      describe 'apply aggregate operation' do
        it 'add count operation to the query' do
          aggregation = Aggregation.new(operation: 'Count')
          query_aggregate = described_class.new(collection, aggregation, Filter.new)
          query_aggregate.get

          expect(query_aggregate.query.pipeline).to eq(
            [
              { '$group' => { '_id' => {}, 'value' => { '$count' => {} } } },
              { '$project' => { '_id' => 0, 'group' => { '$literal' => {} }, 'value' => '$value' } }
            ]
          )
        end

        it 'add sum operation to the query' do
          aggregation = Aggregation.new(operation: 'Sum', field: 'rating')
          query_aggregate = described_class.new(collection, aggregation, Filter.new)
          query_aggregate.get

          expect(query_aggregate.query.pipeline).to eq(
            [
              { '$group' => { '_id' => {}, 'value' => { '$sum' => 'rating' } } },
              { '$project' => { '_id' => 0, 'group' => { '$literal' => {} }, 'value' => '$value' } }
            ]
          )
        end

        it 'add avg operation to the query' do
          aggregation = Aggregation.new(operation: 'Avg', field: 'rating')
          query_aggregate = described_class.new(collection, aggregation, Filter.new)
          query_aggregate.get

          expect(query_aggregate.query.pipeline).to eq(
            [
              { '$group' => { '_id' => {}, 'value' => { '$avg' => 'rating' } } },
              { '$project' => { '_id' => 0, 'group' => { '$literal' => {} }, 'value' => '$value' } }
            ]
          )
        end

        it 'add min operation to the query' do
          aggregation = Aggregation.new(operation: 'Min', field: 'rating')
          query_aggregate = described_class.new(collection, aggregation, Filter.new)
          query_aggregate.get

          expect(query_aggregate.query.pipeline).to eq(
            [
              { '$group' => { '_id' => {}, 'value' => { '$min' => 'rating' } } },
              { '$project' => { '_id' => 0, 'group' => { '$literal' => {} }, 'value' => '$value' } }
            ]
          )
        end

        it 'add max operation to the query' do
          aggregation = Aggregation.new(operation: 'Max', field: 'rating')
          query_aggregate = described_class.new(collection, aggregation, Filter.new)
          query_aggregate.get

          expect(query_aggregate.query.pipeline).to eq(
            [
              { '$group' => { '_id' => {}, 'value' => { '$max' => 'rating' } } },
              { '$project' => { '_id' => 0, 'group' => { '$literal' => {} }, 'value' => '$value' } }
            ]
          )
        end
      end
    end
  end
end
