require 'spec_helper'
require 'shared/caller'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Computed
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Decorators
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query

      describe ComputeCollectionDecorator do
        include_context 'with caller'
        subject(:compute_collection_decorator) { described_class }

        before do
          datasource = Datasource.new
          collection_book = collection_build(
            name: 'book',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'author_id' => ColumnSchema.new(column_type: 'String'),
                'author' => Relations::ManyToOneSchema.new(
                  foreign_key: 'author_id',
                  foreign_collection: 'person',
                  foreign_key_target: 'id'
                ),
                'title' => ColumnSchema.new(column_type: 'String')
              }
            }
          )

          collection_person = collection_build(
            name: 'person',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'first_name' => ColumnSchema.new(column_type: 'String'),
                'last_name' => ColumnSchema.new(column_type: 'String'),
                'book' => Relations::OneToOneSchema.new(
                  origin_key: 'author_id',
                  origin_key_target: 'id',
                  foreign_collection: 'book'
                )
              }
            }
          )

          collection_address = collection_build(
            name: 'address',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'addressable_id' => ColumnSchema.new(column_type: 'Number'),
                'addressable_type' => ColumnSchema.new(column_type: 'String'),
                'street' => ColumnSchema.new(column_type: 'String'),
                'addressable' => Relations::PolymorphicManyToOneSchema.new(
                  foreign_key_type_field: 'addressable_type',
                  foreign_collections: ['person'],
                  foreign_key_targets: { 'person' => 'id' },
                  foreign_key: 'addressable_id'
                )
              }
            }
          )

          records = [
            {
              'id' => 1,
              'author_id' => 1,
              'author' => { 'id' => 1, 'first_name' => 'Isaac', 'last_name' => 'Asimov' },
              'title' => 'Foundation'
            },
            {
              'id' => 2,
              'author_id' => 2,
              'author' => { 'id' => 2, 'first_name' => 'Edward O.', 'last_name' => 'Thorp' },
              'title' => 'Beat the dealer'
            }
          ]

          allow(collection_book).to receive(:list).and_return(records)
          allow(collection_book).to receive(:aggregate) do |caller, _filter, aggregation, limit|
            aggregation.apply(records, caller.timezone, limit)
          end

          datasource.add_collection(collection_book)
          datasource.add_collection(collection_person)
          datasource.add_collection(collection_address)

          datasource_decorator = DatasourceDecorator.new(datasource, compute_collection_decorator)

          @new_books = datasource_decorator.get_collection('book')
          @new_persons = datasource_decorator.get_collection('person')
          @new_addresses = datasource_decorator.get_collection('address')
        end

        it 'registerComputed should throw if defining a field with no dependencies' do
          expect do
            @new_books.register_computed(
              'newField',
              ComputedDefinition.new(
                column_type: 'String',
                dependencies: [],
                values: proc { |records| records }
              )
            )
          end.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, "🌳🌳🌳 Computed field 'newField' must have at least one dependency.")
        end

        it 'registerComputed should throw if defining a field with polymorphic dependencies' do
          expect do
            @new_addresses.register_computed(
              'newField',
              ComputedDefinition.new(
                column_type: 'String',
                dependencies: ['addressable:foo'],
                values: proc { |records| records }
              )
            )
          end.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            '🌳🌳🌳 Dependencies over a polymorphic relations(address.addressable) are forbidden'
          )
        end

        it 'registerComputed should throw if defining a field with missing dependencies' do
          expect do
            @new_books.register_computed(
              'newField',
              ComputedDefinition.new(
                column_type: 'String',
                dependencies: ['__nonExisting__'],
                values: proc { |records| records }
              )
            )
          end.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ValidationError, "🌳🌳🌳 Column not found: 'book.__nonExisting__'")
        end

        it 'registerComputed should throw if defining a field with invalid dependencies' do
          expect do
            @new_books.register_computed(
              'newField',
              ComputedDefinition.new(
                column_type: 'String',
                dependencies: ['author'],
                values: proc { |records| records }
              )
            )
          end.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ValidationError, "🌳🌳🌳 Unexpected field type: 'book.author' (found 'ManyToOne' expected 'Column')")
        end

        it 'throws when adding field with name including space' do
          allow(@new_persons).to receive(:name).and_return('person')
          expect do
            @new_persons.register_computed(
              'full name',
              ComputedDefinition.new(
                column_type: 'String',
                dependencies: ['first_name', 'last_name'],
                values: proc { |records| records }
              )
            )
          end.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ValidationError)
        end

        context 'with a computed' do
          before do
            @new_persons.register_computed(
              'fullName',
              ComputedDefinition.new(
                column_type: 'String',
                dependencies: ['first_name', 'last_name'],
                values: proc { |records| records.map { |record| "#{record["first_name"]} #{record["last_name"]}" } }
              )
            )
          end

          it 'the schemas should contain the field' do
            expect(@new_persons.schema[:fields]).to have_key('fullName')
          end

          it 'list() result should contain the computed' do
            records = @new_books.list(
              caller,
              Filter.new,
              Projection.new(['title', 'author:fullName'])
            )

            expect(records).to eq([
                                    { 'title' => 'Foundation', 'author' => { 'fullName' => 'Isaac Asimov' } },
                                    { 'title' => 'Beat the dealer', 'author' => { 'fullName' => 'Edward O. Thorp' } }
                                  ])
          end

          it 'aggregate() should use the child implementation when relevant' do
            rows = @new_books.aggregate(
              caller,
              Filter.new,
              Aggregation.new(operation: 'Count')
            )

            expect(rows).to eq([{ value: 2, group: {} }])
          end

          it 'aggregate() should work with computed' do
            rows = @new_books.aggregate(
              caller,
              Filter.new,
              Aggregation.new(operation: 'Min', field: 'author:fullName')
            )

            expect(rows).to eq([{ value: 'Edward O. Thorp', group: {} }])
          end
        end
      end
    end
  end
end
