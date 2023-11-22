require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Query
      include ForestAdminDatasourceToolkit::Schema
      describe Aggregation do
        it 'raise if the operation is invalid' do
          expect do
            described_class.new(operation: 'foo')
          end.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            '🌳🌳🌳 Aggregate operation foo not allowed'
          )
        end

        context 'when projection is called' do
          it 'works with a null field and an empty groups' do
            aggregation = described_class.new(operation: 'Count')

            expect(aggregation.projection).to eq(Projection.new([]))
          end

          it 'works with a field and a groups' do
            aggregation = described_class.new(operation: 'Count', field: 'aggregateField',
                                              groups: [{ field: 'groupField' }])

            expect(aggregation.projection).to eq(Projection.new(['aggregateField', 'groupField']))
          end
        end

        context 'when override is called' do
          it 'works with one arg' do
            aggregation = described_class.new(operation: 'Count')

            expect(aggregation.override(operation: 'Sum')).eql?(described_class.new(operation: 'Sum'))
          end

          it 'works with all args' do
            aggregation = described_class.new(operation: 'Count')

            expect(aggregation.override(operation: 'Sum', field: 'aggregateField', groups: [{ field: 'groupField' }]))
              .eql?(described_class.new(operation: 'Sum', field: 'aggregateField', groups: [{ field: 'groupField' }]))
          end
        end

        context 'when apply is called' do
          it 'works with records, timezone and limit null' do
            aggregation = described_class.new(operation: 'Count')
            records = [
              { 'id' => 1 },
              { 'id' => 1 },
              { 'id' => 1 },
              { 'id' => 2 },
              { 'id' => 2 },
              { 'id' => 2 }
            ]

            expect(aggregation.apply(records, 'Europe/Paris')).to eq([{ group: {}, value: 6 }])
          end

          it 'works with records, timezone and limit null on Avg operation' do
            aggregation = described_class.new(operation: 'Avg', field: 'id')
            records = [
              { 'id' => 1 },
              { 'id' => 2 },
              { 'id' => 3 }
            ]

            expect(aggregation.apply(records, 'Europe/Paris')).to eq([{ group: {}, value: 2 }])
          end

          it 'works with group field on year' do
            aggregation = described_class.new(operation: 'Avg', field: 'field',
                                              groups: [{ field: 'groupField', operation: 'Year' }])
            records = [
              { 'field' => 5, 'groupField' => '2022-05-01' },
              { 'field' => 10, 'groupField' => '2022-05-01' },
              { 'field' => 15, 'groupField' => '2022-01-02' },
              { 'field' => 10, 'groupField' => '2023-07-11' }
            ]

            expect(aggregation.apply(records, 'Europe/Paris')).to eq([
                                                                       { group: { 'groupField' => '2022-01-01' },
                                                                         value: 10 },
                                                                       { group: { 'groupField' => '2023-01-01' },
                                                                         value: 10 }
                                                                     ])
          end

          it 'works with group field on month' do
            aggregation = described_class.new(operation: 'Avg', field: 'field',
                                              groups: [{ field: 'groupField', operation: 'Month' }])
            records = [
              { 'field' => 5, 'groupField' => '2022-05-01' },
              { 'field' => 5, 'groupField' => '2022-05-01' },
              { 'field' => 10, 'groupField' => '2022-01-02' },
              { 'field' => 1, 'groupField' => '2023-07-11' }
            ]

            expect(aggregation.apply(records, 'Europe/Paris')).to eq([
                                                                       { group: { 'groupField' => '2022-05-01' },
                                                                         value: 5 },
                                                                       { group: { 'groupField' => '2022-01-01' },
                                                                         value: 10 },
                                                                       { group: { 'groupField' => '2023-07-01' },
                                                                         value: 1 }
                                                                     ])
          end

          it 'works with group field on day' do
            aggregation = described_class.new(operation: 'Avg', field: 'field',
                                              groups: [{ field: 'groupField', operation: 'Day' }])
            records = [
              { 'field' => 5, 'groupField' => '2022-05-01' },
              { 'field' => 5, 'groupField' => '2022-05-01' },
              { 'field' => 10, 'groupField' => '2022-01-02' },
              { 'field' => 1, 'groupField' => '2023-07-11' }
            ]

            expect(aggregation.apply(records, 'Europe/Paris')).to eq([
                                                                       { group: { 'groupField' => '2022-05-01' },
                                                                         value: 5 },
                                                                       { group: { 'groupField' => '2022-01-02' },
                                                                         value: 10 },
                                                                       { group: { 'groupField' => '2023-07-11' },
                                                                         value: 1 }
                                                                     ])
          end

          it 'works with group field on day with limit' do
            aggregation = described_class.new(operation: 'Avg', field: 'field',
                                              groups: [{ field: 'groupField', operation: 'Day' }])

            records = [
              { 'field' => 5, 'groupField' => '2022-05-01' },
              { 'field' => 5, 'groupField' => '2022-05-01' },
              { 'field' => 10, 'groupField' => '2022-01-02' },
              { 'field' => 1, 'groupField' => '2023-07-11' }
            ]

            expect(aggregation.apply(records, 'Europe/Paris', 2)).to eq([
                                                                          { group: { 'groupField' => '2022-05-01' },
                                                                            value: 5 },
                                                                          { group: { 'groupField' => '2022-01-02' },
                                                                            value: 10 }
                                                                        ])
          end

          it 'works with group field on week' do
            aggregation = described_class.new(operation: 'Avg', field: 'field',
                                              groups: [{ field: 'groupField', operation: 'Week' }])
            records = [
              { 'field' => 5, 'groupField' => '2022-05-01' },
              { 'field' => 5, 'groupField' => '2022-05-01' },
              { 'field' => 10, 'groupField' => '2022-01-02' },
              { 'field' => 1, 'groupField' => '2023-07-11' }
            ]

            expect(aggregation.apply(records, 'Europe/Paris')).to eq([
                                                                       { group: { 'groupField' => '2022-05-01' },
                                                                         value: 5 },
                                                                       { group: { 'groupField' => '2022-01-01' },
                                                                         value: 10 },
                                                                       { group: { 'groupField' => '2023-07-01' },
                                                                         value: 1 }
                                                                     ])
          end
        end

        context 'when nest is called' do
          it 'returns a new aggregation with field and group prefixed' do
            aggregation = described_class.new(
              operation: 'Sum',
              field: 'aggregateField',
              groups: [{ field: 'groupField', operation: 'Week' }]
            )

            expect(aggregation.nest('prefix'))
              .eql?(described_class.new(
                      operation: 'Sum',
                      field: 'prefix:aggregateField',
                      groups: [{ field: 'prefix:groupField', operation: 'Week' }]
                    ))
          end

          it 'works with null prefix' do
            aggregation = described_class.new(
              operation: 'Sum',
              field: 'aggregateField',
              groups: [{ field: 'groupField', operation: 'Week' }]
            )

            expect(aggregation.nest(nil))
              .eql?(described_class.new(
                      operation: 'Sum',
                      field: 'aggregateField',
                      groups: [{ field: 'groupField', operation: 'Week' }]
                    ))
          end
        end
      end
    end
  end
end
