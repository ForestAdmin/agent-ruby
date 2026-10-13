require 'spec_helper'

module ForestAdminDatasourceMongoid
  module Utils
    RSpec.describe AddNullValues do
      let(:add_null_values_module) { Class.new { include AddNullValues }.new }

      describe '#remove_not_exist_record' do
        it 'returns nil if the record is nil' do
          expect(add_null_values_module.remove_not_exist_record(nil)).to be_nil
        end

        it 'removes record if FOREST_RECORD_DOES_NOT_EXIST key is present' do
          record = { Pipeline::ConditionGenerator::FOREST_RECORD_DOES_NOT_EXIST => true }
          expect(add_null_values_module.remove_not_exist_record(record)).to be_nil
        end

        it 'returns the record unchanged if no special condition is present' do
          record = { 'name' => 'value' }
          expect(add_null_values_module.remove_not_exist_record(record)).to eq(record)
        end

        it 'removes nested object with FOREST_RECORD_DOES_NOT_EXIST key' do
          record = { 'nested' => { Pipeline::ConditionGenerator::FOREST_RECORD_DOES_NOT_EXIST => true } }
          result = add_null_values_module.remove_not_exist_record(record)
          expect(result['nested']).to be_nil
        end
      end

      describe '#add_null_values_on_record' do
        let(:record) { { 'name' => 'value', 'age' => 30 } }
        let(:projection) { %w[name age address] }

        it 'returns nil if the record is nil' do
          expect(add_null_values_module.add_null_values_on_record(nil, projection)).to be_nil
        end

        it 'adds null values for fields not present in the record' do
          result = add_null_values_module.add_null_values_on_record(record, projection)
          expect(result['address']).to be_nil
        end

        it 'does not modify existing fields in the record' do
          result = add_null_values_module.add_null_values_on_record(record, projection)
          expect(result['name']).to eq('value')
        end

        it 'handles nested fields and adds null values' do
          nested_record = { 'person' => { 'name' => 'John' } }
          projection = ['person:name', 'person:age']
          result = add_null_values_module.add_null_values_on_record(nested_record, projection)
          expect(result['person']['age']).to be_nil
        end

        it 'removes nested object with FOREST_RECORD_DOES_NOT_EXIST key' do
          nested_record = { 'person' => { Pipeline::ConditionGenerator::FOREST_RECORD_DOES_NOT_EXIST => true } }
          result = add_null_values_module.add_null_values_on_record(nested_record, ['person:name'])
          expect(result['person']).to be_nil
        end
      end

      describe '#add_null_values' do
        it 'returns an array of modified records without nil values' do
          records = [{ 'name' => 'John' }, { 'name' => 'Jane' }]
          projection = ['name', 'address']
          result = add_null_values_module.add_null_values(records, projection)
          expect(result.length).to eq(2)
          expect(result.first['address']).to be_nil
        end

        it 'filters out nil records from the final result' do
          records = [{ 'name' => 'John' }, nil]
          projection = ['name', 'address']
          result = add_null_values_module.add_null_values(records, projection)
          expect(result.length).to eq(1)
        end

        it 'fills every item of an array relation' do
          records = [{ 'tags' => [{ 'label' => 'a' }, { 'other' => 1 }] }]
          result = add_null_values_module.add_null_values(records, ['tags:label', 'tags:color'])
          expect(result.first['tags']).to eq(
            [{ 'label' => 'a', 'color' => nil }, { 'other' => 1, 'label' => nil, 'color' => nil }]
          )
        end

        it 'removes array items tagged FOREST_RECORD_DOES_NOT_EXIST' do
          missing = { Pipeline::ConditionGenerator::FOREST_RECORD_DOES_NOT_EXIST => true }
          records = [{ 'tags' => [{ 'label' => 'a' }, missing] }]
          result = add_null_values_module.add_null_values(records, ['tags:label'])
          expect(result.first['tags']).to eq([{ 'label' => 'a' }, nil])
        end

        it 'fills nested relations at every depth' do
          records = [{ 'author' => { 'address' => { 'city' => 'Paris' } } }, { 'author' => {} }]
          result = add_null_values_module.add_null_values(records, ['author:address:city', 'author:address:zip', 'author:name'])
          expect(result).to eq(
            [
              { 'author' => { 'name' => nil, 'address' => { 'city' => 'Paris', 'zip' => nil } } },
              { 'author' => { 'name' => nil, 'address' => nil } }
            ]
          )
        end

        it 'keeps keys outside the projection and nested values that are not records' do
          records = [{ 'name' => 'John', 'extra' => 1, 'author' => 'raw' }]
          result = add_null_values_module.add_null_values(records, ['name', 'author:name'])
          expect(result).to eq([{ 'name' => 'John', 'extra' => 1, 'author' => 'raw' }])
        end

        it 'splits the projection paths as many times for one row as for many' do
          build_records = lambda do |count|
            Array.new(count) { { 'id' => 1, 'author' => { 'address' => {} }, 'tags' => [{}, {}] } }
          end
          count_splits = lambda do |records|
            count = 0
            projection = ['id', 'name', 'author:name', 'author:address:city', 'tags:label'].map(&:dup)
            projection.each do |path|
              allow(path).to receive(:split).and_wrap_original do |original, *args|
                count += 1
                original.call(*args)
              end
            end
            add_null_values_module.add_null_values(records, projection)
            count
          end
          one_row = count_splits.call(build_records.call(1))

          expect(count_splits.call(build_records.call(50))).to eq(one_row)
        end
      end
    end
  end
end
