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
          end.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ValidationError,
            /Invalid date truncation operation: 'not_a_real_unit'/
          )
        end
      end

      describe 'SQL Injection Prevention' do
        context 'with malicious operation parameter' do
          it 'blocks SQL injection via DROP TABLE' do
            aggregation = Aggregation.new(
              operation: 'Sum',
              field: 'nb_seats',
              groups: [{ field: 'created_at', operation: "day'); DROP TABLE cars; --" }]
            )

            query_aggregate = described_class.new(collection, aggregation)

            expect do
              query_aggregate.get
            end.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ValidationError,
              /Invalid date truncation operation/
            )
          end

          it 'blocks SQL injection via UNION SELECT' do
            aggregation = Aggregation.new(
              operation: 'Sum',
              field: 'nb_seats',
              groups: [{ field: 'created_at', operation: "day') UNION SELECT password FROM users; --" }]
            )

            query_aggregate = described_class.new(collection, aggregation)

            expect do
              query_aggregate.get
            end.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ValidationError,
              /Invalid date truncation operation/
            )
          end

          it 'blocks SQL injection with semicolons' do
            aggregation = Aggregation.new(
              operation: 'Sum',
              field: 'nb_seats',
              groups: [{ field: 'created_at', operation: 'day; DELETE FROM cars' }]
            )

            query_aggregate = described_class.new(collection, aggregation)

            expect do
              query_aggregate.get
            end.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ValidationError,
              /Invalid date truncation operation/
            )
          end

          it 'blocks arbitrary SQL keywords' do
            %w[DROP DELETE UPDATE INSERT SELECT].each do |keyword|
              aggregation = Aggregation.new(
                operation: 'Sum',
                field: 'nb_seats',
                groups: [{ field: 'created_at', operation: keyword }]
              )

              query_aggregate = described_class.new(collection, aggregation)

              expect do
                query_aggregate.get
              end.to raise_error(
                ForestAdminDatasourceToolkit::Exceptions::ValidationError,
                /Invalid date truncation operation/
              )
            end
          end
        end

        context 'with valid operations' do
          it 'accepts all whitelisted operations' do
            %w[second minute hour day week month quarter year].each do |operation|
              aggregation = Aggregation.new(
                operation: 'Count',
                field: nil,
                groups: [{ field: 'created_at', operation: operation }]
              )

              query_aggregate = described_class.new(collection, aggregation)

              expect do
                query_aggregate.get
              end.not_to raise_error
            end
          end

          it 'accepts operations with different case' do
            %w[DAY Day dAy].each do |operation|
              aggregation = Aggregation.new(
                operation: 'Count',
                field: nil,
                groups: [{ field: 'created_at', operation: operation }]
              )

              query_aggregate = described_class.new(collection, aggregation)

              expect do
                query_aggregate.get
              end.not_to raise_error
            end
          end
        end

        context 'with malicious field names', :db_truncation do
          it 'blocks SQL injection in field parameter' do
            # Mock format_field to return malicious string
            aggregation = Aggregation.new(
              operation: 'Sum',
              field: 'nb_seats',
              groups: [{ field: 'created_at', operation: 'day' }]
            )

            query_aggregate = described_class.new(collection, aggregation)

            # Test the date_trunc_sql method directly with malicious field
            expect do
              query_aggregate.send(:date_trunc_sql, 'day', 'created_at); DROP TABLE cars; --')
            end.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ValidationError,
              /Invalid field: .* does not exist in collection/
            )
          end

          it 'blocks field names with semicolons' do
            aggregation = Aggregation.new(
              operation: 'Sum',
              field: 'nb_seats',
              groups: [{ field: 'created_at', operation: 'day' }]
            )

            query_aggregate = described_class.new(collection, aggregation)

            expect do
              query_aggregate.send(:date_trunc_sql, 'day', 'field; DELETE FROM cars')
            end.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ValidationError,
              /Invalid field: .* does not exist in collection/
            )
          end

          it 'blocks non-existent field names' do
            aggregation = Aggregation.new(
              operation: 'Count',
              field: nil,
              groups: [{ field: 'created_at', operation: 'day' }]
            )

            query_aggregate = described_class.new(collection, aggregation)

            expect do
              query_aggregate.send(:date_trunc_sql, 'day', 'non_existent_field')
            end.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ValidationError,
              /Invalid field: 'non_existent_field' does not exist in collection/
            )
          end

          it 'accepts valid field names with underscores' do
            aggregation = Aggregation.new(
              operation: 'Count',
              field: nil,
              groups: [{ field: 'created_at', operation: 'day' }]
            )

            query_aggregate = described_class.new(collection, aggregation)

            expect do
              query_aggregate.send(:date_trunc_sql, 'day', 'created_at')
            end.not_to raise_error
          end

          it 'accepts valid field names with table prefix' do
            aggregation = Aggregation.new(
              operation: 'Count',
              field: nil,
              groups: [{ field: 'created_at', operation: 'day' }]
            )

            query_aggregate = described_class.new(collection, aggregation)

            expect do
              query_aggregate.send(:date_trunc_sql, 'day', 'cars.created_at')
            end.not_to raise_error
          end
        end
      end
    end
  end
end
