require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Utils
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Exceptions

    describe Record do
      describe 'primary_keys' do
        it 'finds the pks from record' do
          collection = ForestAdminDatasourceToolkit::Collection.new(Datasource.new, '__collection__')
          collection.add_fields(
            {
              'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true),
              'notId' => ColumnSchema.new(column_type: PrimitiveType::STRING),
              'otherId' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true)
            }
          )
          result = described_class.primary_keys(collection, { 'id' => 1, 'notId' => 'foo', 'otherId' => 11 })
          expect(result).to be_a(Array)
          expect(result).to eq([1, 11])
        end

        it 'throws if record has not PK' do
          collection = ForestAdminDatasourceToolkit::Collection.new(Datasource.new, '__collection__')
          collection.add_fields(
            {
              'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true),
              'notId' => ColumnSchema.new(column_type: PrimitiveType::STRING)
            }
          )
          expect do
            described_class.primary_keys(collection,
                                         { 'notId' => 'foo' })
          end.to raise_error(Exceptions::BadRequestError, 'Missing primary key: id')
        end
      end

      describe 'field_value' do
        it 'extracts value' do
          record = { 'relation1' => { 'relation2' => 'value' } }
          value = described_class.field_value(record, 'relation1:relation2')
          expect(value).to eq('value')
        end
      end
    end
  end
end
