require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Chart
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Decorators
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query
      describe ResultBuilder do
        let(:builder) { described_class.new }

        describe 'value' do
          it 'return the expected format' do
            expect(builder.value(34)).to eq({ countCurrent: 34, countPrevious: nil })
            expect(builder.value(34, 45)).to eq({ countCurrent: 34, countPrevious: 45 })
          end
        end

        describe 'distribution' do
          it 'return the expected format' do
            expect(builder.distribution({ a: 10, b: 11 })).to eq(
              [
                { key: 'a', value: 10 },
                { key: 'b', value: 11 }
              ]
            )
          end
        end

        describe 'time_based' do
          it 'return the expected format (Day)' do
            result = builder.time_based(
              'Day',
              {
                '1985-10-26': 1,
                '1985-10-27': 2,
                '1985-10-30': 3
              }
            )

            expect(result).to eq(
              [
                { label: '26/10/1985', values: { value: 1 } },
                { label: '27/10/1985', values: { value: 2 } },
                { label: '28/10/1985', values: { value: 0 } },
                { label: '29/10/1985', values: { value: 0 } },
                { label: '30/10/1985', values: { value: 3 } }
              ]
            )
          end

          it 'return the expected format (Week)' do
            result = builder.time_based(
              'Week',
              {
                '1985-12-26': 1,
                '1986-01-07': 3,
                '1986-01-08': 4
              }
            )

            expect(result).to eq(
              [
                { label: 'W52-1985', values: { value: 1 } },
                { label: 'W01-1986', values: { value: 0 } },
                { label: 'W02-1986', values: { value: 7 } }
              ]
            )
          end

          it 'return the expected format (Month)' do
            result = builder.time_based(
              'Month',
              {
                '1985-10-26': 1,
                '1985-11-27': 2,
                '1986-01-07': 3,
                '1986-01-08': 4
              }
            )

            expect(result).to eq(
              [
                { label: 'Oct 85', values: { value: 1 } },
                { label: 'Nov 85', values: { value: 2 } },
                { label: 'Dec 85', values: { value: 0 } },
                { label: 'Jan 86', values: { value: 7 } }
              ]
            )
          end

          it 'return the expected format (Year)' do
            result = builder.time_based(
              'Year',
              {
                '1985-10-26': 1,
                '1986-01-07': 3,
                '1986-01-08': 4
              }
            )

            expect(result).to eq(
              [
                { label: '1985', values: { value: 1 } },
                { label: '1986', values: { value: 7 } }
              ]
            )
          end

          it 'return empty array when null is given for values property' do
            result = builder.time_based('Year', nil)

            expect(result).to eq([])
          end

          it 'return empty array when empty array is given' do
            result = builder.time_based('Year', [])

            expect(result).to eq([])
          end
        end

        describe 'percentage' do
          it 'return the expected format' do
            expect(builder.percentage(34)).to eq(34)
          end
        end

        describe 'leaderboard' do
          it 'return the expected format' do
            expect(builder.leaderboard({ a: 10, b: 30, c: 20 })).to eq(
              [
                { key: 'b', value: 30 },
                { key: 'c', value: 20 },
                { key: 'a', value: 10 }
              ]
            )
          end
        end

        describe 'smart' do
          it 'return the expected format' do
            expect(builder.smart(34)).to eq(34)
          end
        end

        describe 'multiple_time_based' do
          it 'return return the labels and the key/values for each line' do
            result = builder.multiple_time_based(
              'Year',
              [
                DateTime.parse('1985-10-26'),
                DateTime.parse('1986-01-07'),
                DateTime.parse('1986-01-08'),
                DateTime.parse('1985-10-27')
              ],
              [
                {
                  label: 'firstLine',
                  values: [1, 2, 3, nil]
                },
                {
                  label: 'secondLine',
                  values: [4, 2, 6, 7]
                }
              ]
            )

            expect(result).to eq(
              {
                labels: %w[1985 1986],
                values: [
                  { key: 'firstLine', values: [1, 5] },
                  { key: 'secondLine', values: [11, 8] }
                ]
              }
            )
          end

          describe 'when there are only null values for a time range' do
            it 'displays 0' do
              result = builder.multiple_time_based(
                'Year',
                [
                  DateTime.parse('1985-10-26'),
                  DateTime.parse('1986-01-07'),
                  DateTime.parse('1986-01-08'),
                  DateTime.parse('1985-10-27')
                ],
                [{ label: 'firstLine', values: [nil, 2, 3, nil] }]
              )

              expect(result).to eq(
                {
                  labels: %w[1985 1986],
                  values: [{ key: 'firstLine', values: [0, 5] }]
                }
              )
            end
          end

          describe 'when there is null and number values for a time range' do
            it 'displays a number' do
              result = builder.multiple_time_based(
                'Year',
                [
                  DateTime.parse('1985-10-26'),
                  DateTime.parse('1986-01-07'),
                  DateTime.parse('1986-01-08'),
                  DateTime.parse('1985-10-27')
                ],
                [{ label: 'firstLine', values: [100, 1, 2, nil] }]
              )

              expect(result).to eq(
                {
                  labels: %w[1985 1986],
                  values: [{ key: 'firstLine', values: [100, 3] }]
                }
              )
            end
          end

          describe 'when there is no value for a time range' do
            it 'displays 0' do
              result = builder.multiple_time_based(
                'Year',
                [
                  DateTime.parse('1985-10-26'),
                  DateTime.parse('1986-01-07'),
                  DateTime.parse('1986-01-08'),
                  DateTime.parse('1985-10-27')
                ],
                [{ label: 'firstLine', values: [0] }]
              )

              expect(result).to eq(
                {
                  labels: %w[1985 1986],
                  values: [{ key: 'firstLine', values: [0, 0] }]
                }
              )
            end
          end

          describe 'when there is no date' do
            it 'return empty array labels and null values for the line' do
              result = builder.multiple_time_based('Year', [], [{ label: 'firstLine', values: [0] }])

              expect(result).to eq(
                {
                  labels: [],
                  values: nil
                }
              )
            end
          end

          describe 'when there is no line' do
            it 'return null labels and empty array for values' do
              result = builder.multiple_time_based('Year', [DateTime.parse('1985-10-26')], [])

              expect(result).to eq(
                {
                  labels: nil,
                  values: nil
                }
              )
            end
          end

          describe 'when there are no date and lines' do
            it 'return null labels and values' do
              result = builder.multiple_time_based('Year', nil, nil)

              expect(result).to eq(
                {
                  labels: nil,
                  values: nil
                }
              )
            end
          end
        end
      end
    end
  end
end
