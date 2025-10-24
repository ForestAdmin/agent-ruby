require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Validation
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Exceptions

      describe ValidationCollectionDecorator do
        include_context 'with caller'
        let(:datasource) { ForestAdminDatasourceToolkit::Datasource.new }

        before do
          @collection_book = instance_double(
            ForestAdminDatasourceToolkit::Collection,
            name: 'book',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, is_read_only: true),
                'author_id' => ColumnSchema.new(column_type: 'String'),
                'author' => Relations::ManyToOneSchema.new(
                  foreign_key: 'author_id',
                  foreign_collection: 'person',
                  foreign_key_target: 'id'
                ),
                'title' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::LONGER_THAN, Operators::PRESENT]),
                'sub_title' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::LONGER_THAN])
              }
            },
            datasource: datasource
          )

          @collection_person = instance_double(
            ForestAdminDatasourceToolkit::Collection,
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
            },
            datasource: datasource
          )

          datasource.add_collection(@collection_book)
          datasource.add_collection(@collection_person)

          datasource_decorator = ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator.new(datasource, described_class)

          @decorated_book = datasource_decorator.get_collection('book')
          @decorated_person = datasource_decorator.get_collection('person')
        end

        it 'addValidation() should throw if the field does not exists' do
          expect { @decorated_book.add_validation('__dontExist', { operator: Operators::PRESENT }) }.to raise_error(ValidationError, "Column not found: 'book.__dontExist'")
        end

        it 'addValidation() should throw if the field is readonly' do
          expect { @decorated_book.add_validation('id', { operator: Operators::PRESENT }) }.to raise_error(ForestAdminDatasourceToolkit::Exceptions::UnprocessableError, 'Cannot add validators on a readonly field')
        end

        it 'addValidation() should throw if the field is a relation' do
          expect { @decorated_book.add_validation('author', { operator: Operators::PRESENT }) }.to raise_error(ValidationError, "Unexpected field type: 'book.author' (found 'ManyToOne' expected 'Column')")
        end

        it 'addValidation() should throw if the field is in a relation' do
          expect { @decorated_book.add_validation('author:first_name', { operator: Operators::PRESENT }) }.to raise_error(ForestAdminDatasourceToolkit::Exceptions::UnprocessableError, 'Cannot add validators on a relation, use the foreign key instead')
        end

        context 'with field selection when validating' do
          before do
            @decorated_book.add_validation('title', { operator: Operators::LONGER_THAN, value: 5 })
            @decorated_book.add_validation('sub_title', { operator: Operators::LONGER_THAN, value: 5 })
          end

          it 'validates all fields when creating a record' do
            allow(@collection_book).to receive(:create).and_return(nil)

            expect { @decorated_book.create(caller, [{ 'title' => 'longtitle', 'sub_title' => '' }]) }.to raise_error(ValidationError, 'sub_title failed validation rule : longer_than(5)')
          end

          it 'validates only changed fields when updating' do
            allow(@decorated_book).to receive(:update).and_return(nil)
            @decorated_book.update(caller, Filter.new, { 'title' => 'longtitle' })

            expect(@decorated_book).to have_received(:update)
          end
        end

        context 'with validation when setting to null (null allowed)' do
          before do
            @decorated_book.add_validation('title', { operator: Operators::LONGER_THAN, value: 5 })
          end

          it 'forwards create that respect the rule' do
            allow(@decorated_book).to receive(:create).and_return(nil)

            expect(@decorated_book.create(caller, [{ title: nil }])).to be_nil
          end
        end

        context 'with validation on a defined value' do
          before do
            @decorated_book.add_validation('title', { operator: Operators::LONGER_THAN, value: 5 })
          end

          it 'forwards create that respect the rule' do
            allow(@collection_book).to receive(:create).and_return(nil)
            @decorated_book.create(caller, [{ title: '123456' }])

            expect(@collection_book).to have_received(:create)
          end

          it 'forwards updates that respect the rule' do
            allow(@collection_book).to receive(:update).and_return(nil)
            @decorated_book.update(caller, Filter.new, { title: '123456' })

            expect(@collection_book).to have_received(:update)
          end

          it 'rejects create that do not respect the rule' do
            allow(@collection_book).to receive(:create).and_return(nil)

            expect { @decorated_book.create(caller, [{ 'title' => '1234' }]) }.to raise_error(ValidationError, 'title failed validation rule : longer_than(5)')
          end

          it 'rejects updates that do not respect the rule' do
            allow(@collection_book).to receive(:update).and_return(true)

            expect { @decorated_book.update(caller, Filter.new, { 'title' => '1234' }) }.to raise_error(ValidationError, 'title failed validation rule : longer_than(5)')
          end
        end
      end
    end
  end
end
