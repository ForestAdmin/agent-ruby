require 'spec_helper'
require 'ostruct'

module ForestAdminDatasourceToolkit
  module Validations
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Exceptions

    describe RecordValidator do
      let(:datasource) { Datasource.new }

      context 'when the field is a column' do
        before do
          @collection = Collection.new(datasource, '__collection__')
          @collection.add_fields(
            {
              'name' => ColumnSchema.new(column_type: Concerns::PrimitiveTypes::STRING)
            }
          )

          datasource.add_collection(@collection)
        end

        context 'when the given field is not in the collection' do
          it 'throws an error' do
            expect do
              described_class.validate(@collection, { 'unknownField' => 'this field is not defined in the collection' })
            end.to raise_error(ForestException, 'Unknown field unknownField')
          end
        end

        context 'when the given field is a column and valid' do
          it 'does not throw an error' do
            expect do
              described_class.validate(@collection, { 'name' => 'this field is in collection' })
            end.not_to raise_error
          end
        end

        context 'when the given field is a number and the given value is an array' do
          it 'throws an error' do
            expect do
              described_class.validate(@collection, { 'name' => [100] })
            end.to raise_error(ValidationError, "The given value has a wrong type for 'name': 100.\n Expects [\"String\", nil]")
          end
        end
      end

      context 'when the field is a relation' do
        before do
          @collection_book = instance_double(
            Collection,
            name: 'book',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'relation' => Relations::OneToOneSchema.new(
                  origin_key: 'owner_id',
                  origin_key_target: 'id',
                  foreign_collection: 'owner'
                )
              }
            },
            datasource: datasource
          )

          @collection_owner = instance_double(
            Collection,
            name: 'owner',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'name' => ColumnSchema.new(column_type: 'String')
              }
            }
          )

          datasource.add_collection(@collection_book)
          datasource.add_collection(@collection_owner)
        end

        it 'does not throw an error when the record data match the collection schema' do
          expect do
            described_class.validate(datasource.get_collection('book'), { 'relation' => { 'name' => 'this field is in collection' } })
          end.not_to raise_error
        end

        it 'throws an error when the record data doest not match the collection' do
          expect do
            described_class.validate(datasource.get_collection('book'), { 'relation' => { 'fieldNotExist' => 'a name' } })
          end.to raise_error(ForestException, 'Unknown field fieldNotExist')
        end

        it 'throws an error when the relation is an empty object' do
          expect do
            described_class.validate(datasource.get_collection('book'), { 'relation' => {} })
          end.to raise_error(ForestException, 'The record data is empty')
        end

        it 'throws an error when the relation is nil' do
          expect do
            described_class.validate(datasource.get_collection('book'), { 'relation' => nil })
          end.to raise_error(ForestException, 'The record data is empty')
        end
      end

      context 'when the given field is a oneToMany relation' do
        before do
          @collection_book = instance_double(
            Collection,
            name: 'book',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'owner_id' => ColumnSchema.new(column_type: 'Number'),
                'relation' => Relations::OneToManySchema.new(
                  foreign_collection: 'owner',
                  origin_key: 'owner_id',
                  origin_key_target: 'id'
                )
              }
            },
            datasource: datasource
          )

          @collection_owner = instance_double(
            Collection,
            name: 'owner',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'name' => ColumnSchema.new(column_type: 'String')
              }
            }
          )

          datasource.add_collection(@collection_book)
          datasource.add_collection(@collection_owner)
        end

        it 'throws an error' do
          expect do
            described_class.validate(datasource.get_collection('book'), { 'relation' => { 'name' => 'a name' } })
          end.to raise_error(ForestException, "Unexpected schema type 'OneToMany' while traversing record")
        end
      end

      context 'when the given field is a ManyToOne relation' do
        before do
          @collection_book = instance_double(
            Collection,
            name: 'book',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'owner_id' => ColumnSchema.new(column_type: 'Number'),
                'relation' => Relations::ManyToOneSchema.new(
                  foreign_key: 'owner_id',
                  foreign_collection: 'owner',
                  foreign_key_target: 'id'
                )
              }
            },
            datasource: datasource
          )

          @collection_owner = instance_double(
            Collection,
            name: 'owner',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'name' => ColumnSchema.new(column_type: 'String')
              }
            }
          )

          datasource.add_collection(@collection_book)
          datasource.add_collection(@collection_owner)
        end

        it 'does not throw an error' do
          expect do
            described_class.validate(datasource.get_collection('book'), { 'relation' => { 'name' => 'a name' } })
          end.not_to raise_error
        end
      end

      context 'when the given field has an unknown column type' do
        before do
          fake_column_schema = Struct.new(:type)
          @collection = Collection.new(datasource, '__collection__')
          @collection.add_fields(
            {
              'id' => fake_column_schema.new(type: 'fake_type_column')
            }
          )

          datasource.add_collection(@collection)
        end

        it 'throws an error' do
          expect do
            described_class.validate(@collection, { 'id' => '1' })
          end.to raise_error(ForestException)
        end
      end
    end
  end
end
