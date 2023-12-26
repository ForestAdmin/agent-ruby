require 'spec_helper'
require 'shared/caller'

module ForestAdminAgent
  module Utils
    include ForestAdminDatasourceToolkit
    include ForestAdminDatasourceToolkit::Schema

    describe Id do
      let(:datasource) do
        datasource = Datasource.new
        collection_person = Collection.new(datasource, 'person')
        collection_person.add_fields(
          {
            'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
            'first_name' => ColumnSchema.new(column_type: 'String'),
            'last_name' => ColumnSchema.new(column_type: 'String')
          }
        )

        collection_pks = Collection.new(datasource, 'pks')
        collection_pks.add_fields(
          {
            'key1' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
            'key2' => ColumnSchema.new(column_type: 'Number', is_primary_key: true)
          }
        )

        collection_foo = Collection.new(datasource, 'foo')
        collection_foo.add_fields(
          {
            'name' => ColumnSchema.new(column_type: 'String')
          }
        )

        datasource.add_collection(collection_person)
        datasource.add_collection(collection_pks)
        datasource.add_collection(collection_foo)

        datasource
      end

      describe 'unpack_id' do
        context 'when collection has one pk' do
          it 'return the list of id value' do
            collection = datasource.get_collection('person')
            expect(described_class.unpack_id(collection, 1)).to eq([1])
          end

          it 'raise when not expected number of pks is unpack' do
            collection = datasource.get_collection('person')

            expect do
              described_class.unpack_id(collection, '1|foo')
            end.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ForestException,
              '🌳🌳🌳 Expected 1 primary keys, found 2'
            )
          end
        end

        context 'when collection has multiple pks' do
          it 'return the list of id value' do
            collection = datasource.get_collection('pks')
            expect(described_class.unpack_id(collection, '1|1')).to eq([1, 1])
          end

          it 'raise when not expected number of pks is unpack' do
            collection = datasource.get_collection('pks')

            expect do
              described_class.unpack_id(collection, '1')
            end.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ForestException,
              '🌳🌳🌳 Expected 2 primary keys, found 1'
            )
          end
        end
      end

      describe 'unpack_ids' do
        it 'return an array of list id values' do
          collection = datasource.get_collection('pks')
          expect(described_class.unpack_ids(collection, ['1|1'])).to eq([[1, 1]])
        end
      end

      describe 'parse_selection_ids' do
        it 'return a hash with excluded_ids' do
          collection = datasource.get_collection('person')
          args = {
            'data' => {
              'attributes' => {
                'ids' => %w[1 2 3],
                'collection_name' => 'User',
                'parent_collection_name' => nil,
                'parent_collection_id' => nil,
                'parent_association_name' => nil,
                'all_records' => true,
                'all_records_subset_query' => [
                  'fields[Car]' => 'id,first_name,last_name',
                  'page[number]' => 1,
                  'page[size]' => 15
                ],
                'all_records_ids_excluded' => ['4'],
                'smart_action_id' => nil
              }
            }
          }

          expect(described_class.parse_selection_ids(collection, args)).to eq({ are_excluded: true, ids: [[4]] })
        end

        it 'return a hash with ids' do
          collection = datasource.get_collection('person')
          args = {
            'data' => {
              'attributes' => {
                'ids' => %w[1 2 3],
                'collection_name' => 'User',
                'parent_collection_name' => nil,
                'parent_collection_id' => nil,
                'parent_association_name' => nil,
                'all_records' => false,
                'all_records_subset_query' => [
                  'fields[Car]' => 'id,first_name,last_name',
                  'page[number]' => 1,
                  'page[size]' => 15
                ],
                'all_records_ids_excluded' => ['4'],
                'smart_action_id' => nil
              }
            }
          }

          expect(described_class.parse_selection_ids(collection, args)).to eq(
            {
              are_excluded: false,
              ids: [[1], [2], [3]]
            }
          )
        end
      end

      describe 'when pack_id is called' do
        it 'return the id value' do
          collection = datasource.get_collection('person')
          expect(described_class.pack_id(collection, { 'id' => 1, 'foo' => 'bar' })).to eq('1')
        end

        it 'throws when collection does not have any primary keys' do
          collection_foo = datasource.get_collection('foo')
          expect do
            described_class.pack_id(collection_foo, { 'id' => 1, 'foo' => 'bar' })
          end.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            '🌳🌳🌳 This collection has no primary key'
          )
        end
      end

      describe 'when pack_ids is called' do
        it 'return an array of ids' do
          collection = datasource.get_collection('person')
          expect(described_class.pack_ids(collection, [
                                            { 'id' => 1, 'foo' => 'bar' },
                                            { 'id' => 2, 'foo' => 'foo' }
                                          ])).to eq(['1', '2'])
        end
      end
    end
  end
end
