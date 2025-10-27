require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Validations
    include ForestAdminDatasourceToolkit::Schema::Concerns
    describe TypeGetter do
      context 'when get is called' do
        context 'when the value is a number' do
          it 'the expected type' do
            expect(described_class.get(1526, 'Number')).to eq('Number')
          end
        end

        context 'when the value is a json' do
          it 'returns the expected type' do
            expect(described_class.get({ message: 'hello' }.to_json, 'Json')).to eq('Json')
          end

          context 'when the value is an array of string and the expected type is json' do
            it 'returns the expected type' do
              expect(described_class.get(['item1'], 'Json')).to eq('Json')
            end
          end

          context 'when the value is an array of plain object the expected type is json' do
            it 'returns the expected type' do
              expect(described_class.get([{ foo: 'bar' }], 'Json')).to eq('Json')
            end
          end

          context 'when the value is a valid JSON' do
            it 'returns the expected type' do
              expect(described_class.get('item1', 'Json')).to eq('Json')
            end
          end
        end

        context 'when the value is an object' do
          it 'returns Json' do
            expect(described_class.get({ message: 'hello' }, 'Json')).to eq('Json')
          end
        end

        context 'when the value is a date' do
          context 'when it is a ruby date' do
            it 'returns the expected type' do
              expect(described_class.get(Date.new, 'Date')).to eq('Date')
            end
          end

          context 'when it is a date without time' do
            it 'returns the expected type' do
              expect(described_class.get('2016-05-25', PrimitiveTypes::DATE_ONLY)).to eq(PrimitiveTypes::DATE_ONLY)
            end
          end

          context 'when it is a date with time' do
            it 'returns the expected type' do
              expect(described_class.get('2016-05-25T09:24:15.123', 'Date')).to eq('Date')
            end
          end

          context 'when there is only the time' do
            it 'returns the expected type' do
              expect(described_class.get('09:24:15.123', 'Date')).to eq('Timeonly')
            end
          end
        end

        context 'when the value is a hash with array of hash type_context (embedded documents)' do
          it 'returns Json type' do
            value = { 'street' => '19 street', 'city' => 'Springfield', 'zip_code' => '12345' }
            type_context = [{ 'street' => 'String', 'city' => 'String', 'zip_code' => 'String' }]
            expect(described_class.get(value, type_context)).to eq('Json')
          end
        end

        context 'when the value is a hash with hash type_context (embedded document)' do
          it 'returns Json type' do
            value = { 'street' => '19 street', 'city' => 'Springfield' }
            type_context = { 'street' => 'String', 'city' => 'String' }
            expect(described_class.get(value, type_context)).to eq('Json')
          end
        end

        context 'when the value is an array' do
          it 'returns Json type' do
            value = [{ 'street' => '19 street' }, { 'street' => 'test' }]
            type_context = [{ 'street' => 'String' }]
            expect(described_class.get(value, type_context)).to eq('Json')
          end
        end

        context 'when the value is a string' do
          context 'when the value is a json and the given context is a String' do
            it 'returns the expected type' do
              expect(described_class.get({ message: 'hello' }.to_json, 'String')).to eq('String')
            end
          end

          context 'when the given context is an Enum' do
            it 'returns the expected type' do
              expect(described_class.get('an enum value', 'Enum')).to eq('Enum')
            end
          end

          context 'when it is a date and the given context is a String' do
            it 'returns the expected type' do
              expect(described_class.get('2016-05-25', 'String')).to eq('String')
            end
          end

          context 'when it is an uuid' do
            it 'returns the expected type' do
              expect(described_class.get('2d162303-78bf-599e-b197-93590ac3d315', 'Uuid')).to eq('Uuid')
            end
          end

          context 'when the value is an uuid and the given context is a String' do
            it 'returns the expected type' do
              expect(described_class.get('2d162303-78bf-599e-b197-93590ac3d315', 'String')).to eq('String')
            end
          end

          context 'when the value is a number and the given context is a String' do
            it 'returns the expected type' do
              expect(described_class.get('12', 'String')).to eq('String')
            end
          end

          context 'when the value is a numeric string and the given context is a Number' do
            it 'returns Number type' do
              expect(described_class.get('27', 'Number')).to eq('Number')
            end

            it 'returns Number type for negative numbers' do
              expect(described_class.get('-42', 'Number')).to eq('Number')
            end

            it 'returns Number type for decimal numbers' do
              expect(described_class.get('3.14', 'Number')).to eq('Number')
            end

            it 'returns Number type for large integers' do
              expect(described_class.get('9223372036854775807', 'Number')).to eq('Number')
            end
          end

          context 'when it is not an uuid or a number' do
            it 'returns the expected type' do
              expect(described_class.get('a string', 'String')).to eq('String')
            end
          end
        end
      end
    end
  end
end
