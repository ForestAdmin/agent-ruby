require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Schema
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Exceptions

      describe SchemaCollectionDecorator do
        subject(:schema_collection_decorator) { described_class }

        it 'overwrites fields from the schema' do
          collection = ForestAdminDatasourceToolkit::Collection.new(nil, 'test')
          collection.schema[:countable] = true

          decorator = schema_collection_decorator.new(collection, nil)
          decorator.override_schema(countable: false)

          expect(collection.schema[:countable]).to be true
          expect(decorator.schema[:countable]).to be false
        end

        describe 'disable_field_filtering' do
          let(:collection) do
            collection = ForestAdminDatasourceToolkit::Collection.new(nil, 'book')
            collection.add_fields(
              {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: ['equal']),
                'author_id' => ColumnSchema.new(column_type: 'Number', filter_operators: %w[equal in]),
                'author' => Relations::ManyToOneSchema.new(
                  foreign_key: 'author_id', foreign_key_target: 'id', foreign_collection: 'person'
                ),
                'cover' => Relations::OneToOneSchema.new(
                  origin_key: 'book_id', origin_key_target: 'id', foreign_collection: 'cover'
                ),
                'reviews' => Relations::OneToManySchema.new(
                  origin_key: 'book_id', origin_key_target: 'id', foreign_collection: 'review'
                ),
                'tags' => Relations::ManyToManySchema.new(
                  origin_key: 'book_id', origin_key_target: 'id', foreign_key: 'tag_id', foreign_key_target: 'id',
                  foreign_collection: 'tag', through_collection: 'book_tag'
                )
              }
            )
            collection
          end
          let(:decorator) { schema_collection_decorator.new(collection, nil) }

          it 'removes the operators of a column without touching the child collection' do
            decorator.disable_field_filtering('author_id')

            expect(decorator.schema[:fields]['author_id'].filter_operators).to eq([])
            expect(collection.schema[:fields]['author_id'].filter_operators).to eq(%w[equal in])
          end

          it 'marks a many to one as not filterable without touching the child collection' do
            decorator.disable_field_filtering('author')

            expect(decorator.schema[:fields]['author'].is_filterable).to be false
            expect(decorator.schema[:fields]['author'].foreign_key).to eq('author_id')
            expect(collection.schema[:fields]['author'].is_filterable).to be true
          end

          it 'marks a one to one as not filterable' do
            decorator.disable_field_filtering('cover')

            expect(decorator.schema[:fields]['cover'].is_filterable).to be false
          end

          it 'keeps the schema overrides' do
            decorator.override_schema(countable: false)
            decorator.disable_field_filtering('author_id')

            expect(decorator.schema[:countable]).to be false
            expect(decorator.schema[:fields]['author_id'].filter_operators).to eq([])
          end

          it 'raises on a primary key' do
            expect { decorator.disable_field_filtering('id') }.to raise_error(
              ValidationError, "Cannot disable filtering on primary key 'book.id'"
            )
          end

          it 'raises on a one to many' do
            expect { decorator.disable_field_filtering('reviews') }.to raise_error(
              ValidationError,
              "Unexpected field type: 'book.reviews' (found 'OneToMany' expected 'Column', 'ManyToOne' or 'OneToOne')"
            )
          end

          it 'raises on a many to many' do
            expect { decorator.disable_field_filtering('tags') }.to raise_error(
              ValidationError,
              "Unexpected field type: 'book.tags' (found 'ManyToMany' expected 'Column', 'ManyToOne' or 'OneToOne')"
            )
          end

          it 'raises on an unknown field' do
            expect { decorator.disable_field_filtering('unknown') }.to raise_error(
              ValidationError, "Field not found: 'book.unknown'"
            )
          end
        end
      end
    end
  end
end
