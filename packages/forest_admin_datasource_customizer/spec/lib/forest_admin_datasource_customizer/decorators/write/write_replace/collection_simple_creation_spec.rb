require 'spec_helper'
require 'shared/caller'

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

          it 'when no rewriting is defined, should do nothing' do
            record = { 'name' => 'a name' }
            allow(@collection_book).to receive(:create).and_return(record)
            result = @decorated_book.create(caller, record)

            expect(result).to eq(record)
            expect(@collection_book).to have_received(:create).with(caller, record)
          end

          context 'when rewrite the record' do
            it 'with a empty handler' do
              record = { 'name' => 'a name', 'age' => 'some age' }
              allow(@collection_book).to receive(:create).and_return(record)

              @decorated_book.replace_field_writing('name') do
                {}
              end
              result = @decorated_book.create(caller, record)

              expect(result).to eq(record)
              expect(@collection_book).to have_received(:create).with(caller, { 'age' => 'some age' })
            end

            it 'when writing on the same field in the handler' do
              record = { 'name' => 'another name' }
              allow(@collection_book).to receive(:create).and_return(record)

              @decorated_book.replace_field_writing('name') do
                record
              end
              result = @decorated_book.create(caller, { 'name' => 'a name' })

              expect(result).to eq(record)
              expect(@collection_book).to have_received(:create).with(caller, { 'name' => 'another name' })
            end

            it 'when writing on another field in the handler' do
              record = { 'age' => 'some age' }
              allow(@collection_book).to receive(:create).and_return(record)

              @decorated_book.replace_field_writing('name') do
                record
              end
              @decorated_book.create(caller, { 'name' => 'a name' })

              expect(@collection_book).to have_received(:create).with(caller, { 'age' => 'some age' })
            end

            it 'when unrelated rewritten are used in parallel' do
              @decorated_book.replace_field_writing('age') do
                { 'age' => 'new age' }
              end

              @decorated_book.replace_field_writing('price') do
                { 'price' => 'new price' }
              end

              record = { 'name' => 'name', 'price' => 'price', 'age' => 'age' }
              allow(@collection_book).to receive(:create).and_return({ 'name' => 'name', 'age' => 'new age', 'price' => 'new price' })
              @decorated_book.create(caller, record)

              expect(@collection_book).to have_received(:create).with(caller, { 'name' => 'name', 'age' => 'new age', 'price' => 'new price' })
            end

            it 'when doing nested rewriting in the handler' do
              @decorated_book.replace_field_writing('name') do
                { 'age' => 'some age' }
              end

              @decorated_book.replace_field_writing('age') do
                { 'price' => 'some price' }
              end

              record = { 'name' => 'a name' }
              allow(@collection_book).to receive(:create).and_return({ 'age' => 'some age', 'price' => 'some price' })

              @decorated_book.create(caller, record)

              expect(@collection_book).to have_received(:create).with(caller, { 'price' => 'some price' })
            end
          end

          context 'when the handler throws' do
            it 'when two handlers request conflicting updates' do
              @decorated_book.replace_field_writing('name') do
                { 'price' => '123' }
              end

              @decorated_book.replace_field_writing('age') do
                { 'price' => '456' }
              end

              expect { @decorated_book.create(caller, { 'name' => 'a name', 'age' => 'an age' }) }.to raise_error(ForestException, '🌳🌳🌳 Conflict value on the field price. It received several values.')
            end

            it 'when handlers call themselves recursively' do
              @decorated_book.replace_field_writing('name') do
                { 'age' => 'some age' }
              end
              @decorated_book.replace_field_writing('age') do
                { 'price' => 'some price' }
              end
              @decorated_book.replace_field_writing('price') do
                { 'name' => 'some name' }
              end

              expect { @decorated_book.create(caller, { 'name' => 'a name' }) }.to raise_error(ForestException, '🌳🌳🌳 Conflict value on the field name. It received several values.')
            end

            it 'when the handler returns a unexpected type' do
              @decorated_book.replace_field_writing('age') do
                'RETURN_SHOULD_FAIL'
              end

              expect { @decorated_book.create(caller, { 'age' => '10' }) }.to raise_error(ForestException, '🌳🌳🌳 The write handler of age should return an Hash or nothing.')
            end

            it 'when the handler returns non existent fields' do
              @decorated_book.replace_field_writing('age') do
                { 'author' => 'Asimov' }
              end

              expect { @decorated_book.create(caller, { 'age' => '10' }) }.to raise_error(ForestException, "🌳🌳🌳 Unknown field: 'author'")
            end

            it 'when the handler returns non existent relations' do
              @decorated_book.replace_field_writing('age') do
                { 'author' => { 'lastname' => 'Asimov' } }
              end

              expect { @decorated_book.create(caller, { 'age' => '10' }) }.to raise_error(ForestException, "🌳🌳🌳 Unknown field: 'author'")
            end

            it 'if the customer attemps to update the patch in the handler' do
              @decorated_book.replace_field_writing('name') do |_value, context|
                context.record['ADDED_FIELD'] = 'updating the patch'
              end

              expect { @decorated_book.create(caller, { 'name' => 'orius' }) }.to raise_error(RuntimeError, 'can\'t add a new key into hash during iteration')
            end

            it 'when a handler throws' do
              @decorated_book.replace_field_writing('name') do
                raise 'Some error'
              end

              expect { @decorated_book.create(caller, { 'name' => 'a name' }) }.to raise_error('Some error')
            end

            it 'when not using the appropriate type' do
              allow(@collection_book).to receive(:create)
              @decorated_book.replace_field_writing('name') do
                { 'age' => [1.2] }
              end

              expect { @decorated_book.create(caller, { 'name' => 'a name' }) }.to raise_error(ValidationError, "🌳🌳🌳 The given value has a wrong type for 'age': 1.2.\n Expects [\"String\", nil]")
            end
          end
        end
      end
    end
  end
end
