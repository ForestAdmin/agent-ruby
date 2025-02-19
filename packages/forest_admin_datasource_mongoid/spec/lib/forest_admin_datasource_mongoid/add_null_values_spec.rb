require 'spec_helper'

module ForestAdminDatasourceMongoid
  module Utils
    RSpec.describe AddNullValues do
      let(:include_module) { Class.new { include AddNullValues }.new }

      describe '#remove_not_exist_record' do
        it 'returns nil if the record is nil' do
          expect(include_module.remove_not_exist_record(nil)).to be_nil
        end

        it 'removes record if FOREST_RECORD_DOES_NOT_EXIST key is present' do
          record = { Pipeline::ConditionGenerator::FOREST_RECORD_DOES_NOT_EXIST => true }
          expect(include_module.remove_not_exist_record(record)).to be_nil
        end

        it 'returns the record unchanged if no special condition is present' do
          record = { 'name' => 'value' }
          expect(include_module.remove_not_exist_record(record)).to eq(record)
        end

        it 'removes nested object with FOREST_RECORD_DOES_NOT_EXIST key' do
          record = { 'nested' => { Pipeline::ConditionGenerator::FOREST_RECORD_DOES_NOT_EXIST => true } }
          result = include_module.remove_not_exist_record(record)
          expect(result['nested']).to be_nil
        end
      end

      describe '#add_null_values_on_record' do
        let(:record) { { 'name' => 'value', 'age' => 30 } }
        let(:projection) { %w[name age address] }

        it 'returns nil if the record is nil' do
          expect(include_module.add_null_values_on_record(nil, projection)).to be_nil
        end

        it 'adds null values for fields not present in the record' do
          result = include_module.add_null_values_on_record(record, projection)
          expect(result['address']).to be_nil
        end

        it 'does not modify existing fields in the record' do
          result = include_module.add_null_values_on_record(record, projection)
          expect(result['name']).to eq('value')
        end

        it 'handles nested fields and adds null values' do
          nested_record = { 'person' => { 'name' => 'John' } }
          projection = ['person:name', 'person:age']
          result = include_module.add_null_values_on_record(nested_record, projection)
          expect(result['person']['age']).to be_nil
        end

        it 'removes nested object with FOREST_RECORD_DOES_NOT_EXIST key' do
          nested_record = { 'person' => { Pipeline::ConditionGenerator::FOREST_RECORD_DOES_NOT_EXIST => true } }
          result = include_module.add_null_values_on_record(nested_record, ['person:name'])
          expect(result['person']).to be_nil
        end
      end

      describe '#add_null_values' do
        it 'returns an array of modified records without nil values' do
          records = [{ 'name' => 'John' }, { 'name' => 'Jane' }]
          projection = ['name', 'address']
          result = include_module.add_null_values(records, projection)
          expect(result.length).to eq(2)
          expect(result.first['address']).to be_nil
        end

        it 'filters out nil records from the final result' do
          records = [{ 'name' => 'John' }, nil]
          projection = ['name', 'address']
          result = include_module.add_null_values(records, projection)
          expect(result.length).to eq(1)
        end
      end
    end
  end
end
