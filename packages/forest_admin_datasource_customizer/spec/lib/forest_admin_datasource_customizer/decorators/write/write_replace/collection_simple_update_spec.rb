require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Write
      module WriteReplace
        include ForestAdminDatasourceToolkit::Schema
        include ForestAdminDatasourceToolkit::Components::Query
        include ForestAdminDatasourceToolkit::Exceptions

        describe WriteReplaceCollectionDecorator do
          let(:datasource) { ForestAdminDatasourceToolkit::Datasource.new }
          let(:write_datasource_decorator) { ForestAdminDatasourceCustomizer::Decorators::Write::WriteDatasourceDecorator }
          let(:caller) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }
          let(:filter) { Filter.new }

          before do
            @collection_book = instance_double(
              ForestAdminDatasourceToolkit::Collection,
              name: 'book',
              schema: {
                fields: {
                  'id' => build_numeric_primary_key,
                  'name' => build_column,
                  'age' => build_column,
                  'price' => build_column
                }
              }
            )

            datasource.add_collection(@collection_book)

            datasource_decorator = write_datasource_decorator.new(datasource)
            @decorated_book = datasource_decorator.get_collection('book')
          end

          it 'does nothing when no rewriting is defined' do
            allow(@collection_book).to receive(:update)
            record = { 'name' => 'a name' }
            @decorated_book.update(caller, filter, record)

            expect(@collection_book).to have_received(:update).with(caller, filter, record)
          end

          it 'works with a empty handler' do
            allow(@collection_book).to receive(:update)
            record = { 'name' => 'a name', 'age' => 'some age' }
            @decorated_book.replace_field_writing('name') do
              {}
            end
            @decorated_book.update(caller, filter, record)

            expect(@collection_book).to have_received(:update).with(caller, filter, { 'age' => 'some age' })
          end

          it 'works when writing on the same field in the handler' do
            allow(@collection_book).to receive(:update)
            @decorated_book.replace_field_writing('name') do
              { 'name' => 'another name' }
            end
            @decorated_book.update(caller, filter, { 'name' => 'a name' })

            expect(@collection_book).to have_received(:update).with(caller, filter, { 'name' => 'another name' })
          end

          it 'works when writing on another field in the handler' do
            allow(@collection_book).to receive(:update)
            @decorated_book.replace_field_writing('name') do
              { 'age' => 'some age' }
            end
            @decorated_book.update(caller, filter, { 'name' => 'a name' })

            expect(@collection_book).to have_received(:update).with(caller, filter, { 'age' => 'some age' })
          end

          it 'works when unrelated rewritten are used in parallel' do
            allow(@collection_book).to receive(:update)
            @decorated_book.replace_field_writing('age') do
              { 'age' => 'new age' }
            end
            @decorated_book.replace_field_writing('price') do
              { 'price' => 'new price' }
            end
            @decorated_book.update(caller, filter, { 'name' => 'name', 'price' => 'price', 'age' => 'age' })

            expect(@collection_book).to have_received(:update).with(caller, filter, { 'name' => 'name', 'age' => 'new age', 'price' => 'new price' })
          end

          it 'raises an error when two handlers request conflicting updates' do
            @decorated_book.replace_field_writing('name') do
              { 'price' => '123' }
            end

            @decorated_book.replace_field_writing('age') do
              { 'price' => '456' }
            end

            expect { @decorated_book.update(caller, filter, { 'name' => 'a name', 'age' => 'an age' }) }.to raise_error(ForestAdminDatasourceToolkit::Exceptions::UnprocessableError, 'Conflict value on the field price. It received several values.')
          end

          it 'throws when handlers call themselves recursively' do
            @decorated_book.replace_field_writing('name') do
              { 'age' => 'some age' }
            end

            @decorated_book.replace_field_writing('age') do
              { 'price' => 'some price' }
            end

            @decorated_book.replace_field_writing('price') do
              { 'name' => 'some name' }
            end

            expect { @decorated_book.update(caller, filter, { 'name' => 'a name' }) }.to raise_error(ForestAdminDatasourceToolkit::Exceptions::UnprocessableError, 'Conflict value on the field name. It received several values.')
          end

          it 'throws when the handler returns a unexpected type' do
            @decorated_book.replace_field_writing('age') do
              'RETURN_SHOULD_FAIL'
            end

            expect { @decorated_book.update(caller, filter, { 'age' => '10' }) }.to raise_error(ForestAdminDatasourceToolkit::Exceptions::UnprocessableError, 'The write handler of age should return an Hash or nothing.')
          end

          it 'throws when the handler returns non existent fields' do
            @decorated_book.replace_field_writing('age') do
              { 'author' => 'Asimov' }
            end

            expect { @decorated_book.update(caller, filter, { 'age' => '10' }) }.to raise_error(ForestAdminDatasourceToolkit::Exceptions::NotFoundError, "Unknown field: 'author'")
          end

          it 'throws when the handler returns non existent relations' do
            @decorated_book.replace_field_writing('age') do
              { 'author' => { 'lastname' => 'Asimov' } }
            end

            expect { @decorated_book.update(caller, filter, { 'age' => '10' }) }.to raise_error(ForestAdminDatasourceToolkit::Exceptions::NotFoundError, "Unknown field: 'author'")
          end

          it 'throws if the customer attemps to update the patch in the handler' do
            @decorated_book.replace_field_writing('name') do |_value, context|
              context.record['ADDED_FIELD'] = 'updating the patch'
            end

            expect { @decorated_book.update(caller, filter, { 'name' => 'orius' }) }.to raise_error(RuntimeError, 'can\'t add a new key into hash during iteration')
          end

          it 'throws when a handler throws' do
            @decorated_book.replace_field_writing('name') do
              raise ForestAdminAgent::Error, 'Some error'
            end

            expect { @decorated_book.update(caller, filter, { 'name' => 'a name' }) }.to raise_error(ForestAdminAgent::Error, 'Some error')
          end
        end
      end
    end
  end
end
