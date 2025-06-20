require 'spec_helper'

module ForestAdminDatasourceActiveRecord
  module Utils
    include ForestAdminDatasourceToolkit::Components::Query

    describe QueryAggregate do
      let(:datasource) { Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' }) }
      let(:collection) { Collection.new(datasource, Car) }

      describe 'initialize' do
        it 'initializes with correct attributes' do
          aggregation = Aggregation.new(operation: 'Count', field: nil, groups: [])
          query_aggregate = described_class.new(collection, aggregation)

          expect(query_aggregate.instance_variable_get(:@aggregation)).to eq(aggregation)
          expect(query_aggregate.instance_variable_get(:@operation)).to eq('count')
          expect(query_aggregate.instance_variable_get(:@field)).to eq('*')
        end

        it 'formats field when provided' do
          aggregation = Aggregation.new(operation: 'Count', field: 'price', groups: [])

          query_aggregate = described_class.new(collection, aggregation)

          expect(query_aggregate.instance_variable_get(:@field)).to eq('price')
        end
      end

      it 'sets the limit when provided' do
        aggregation = Aggregation.new(operation: 'Sum', field: 'price', groups: [])
        query_aggregate = described_class.new(collection, aggregation, nil, 10)

        expect(query_aggregate.instance_variable_get(:@limit)).to eq(10)
      end

      describe '#get', :db_truncation do
        before do
          Car.delete_all
          Category.delete_all
          category = Category.create!(label: 'SUV')
          Car.create!(category: category, brand: 'Toyota', nb_seats: 4, created_at: Time.parse('2024-01-01 UTC'))
          Car.create!(category: category, brand: 'Toyota', nb_seats: 5, created_at: Time.parse('2024-01-01 UTC'))
          Car.create!(category: category, brand: 'Ford',   nb_seats: 5, created_at: Time.parse('2024-02-01 UTC'))
        end

        it 'returns aggregated data grouped by a field' do
          aggregation = Aggregation.new(
            operation: 'Sum',
            field: 'nb_seats',
            groups: [{ field: 'brand' }]
          )

          query_aggregate = described_class.new(collection, aggregation)
          result = query_aggregate.get

          expect(result).to contain_exactly(
            { 'value' => 5, 'group' => { 'brand' => 'Ford' } },
            { 'value' => 9, 'group' => { 'brand' => 'Toyota' } }
          )
        end

        it 'returns aggregated data grouped by truncated date' do
          aggregation = Aggregation.new(
            operation: 'Sum',
            field: 'nb_seats',
            groups: [{ field: 'created_at', operation: 'month' }]
          )

          query_aggregate = described_class.new(collection, aggregation)
          result = query_aggregate.get

          expect(result).to contain_exactly(
            { 'value' => 9, 'group' => { 'created_at' => Time.parse('2024-01-01 00:00:00 UTC') } },
            { 'value' => 5, 'group' => { 'created_at' => Time.parse('2024-02-01 00:00:00 UTC') } }
          )
        end

        it 'respects the limit when provided' do
          aggregation = Aggregation.new(
            operation: 'Sum',
            field: 'nb_seats',
            groups: [{ field: 'brand' }]
          )

          query_aggregate = described_class.new(collection, aggregation, nil, 1)
          result = query_aggregate.get

          expect(result.size).to eq(1)
        end

        it 'raises an error when given an unsupported date truncation operation' do
          aggregation = Aggregation.new(
            operation: 'Sum',
            field: 'nb_seats',
            groups: [{ field: 'created_at', operation: 'not_a_real_unit' }]
          )

          query_aggregate = described_class.new(collection, aggregation)

          expect do
            query_aggregate.get
          end.to raise_error(ArgumentError, /Unsupported date truncation operation 'not_a_real_unit'/)
        end
      end
    end
  end
end
