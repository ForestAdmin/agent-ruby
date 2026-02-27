require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Publication
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Exceptions

      describe PublicationCollectionDecorator do
        include_context 'with caller'
        let(:datasource) { ForestAdminDatasourceToolkit::Datasource.new }

        before do
          @collection_book = instance_double(
            ForestAdminDatasourceToolkit::Collection,
            name: 'book',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, is_read_only: true),
                'my_persons' => Relations::ManyToManySchema.new(
                  origin_key: 'book_id',
                  origin_key_target: 'id',
                  foreign_key: 'person_id',
                  foreign_key_target: 'id',
                  foreign_collection: 'person',
                  through_collection: 'book_person'
                ),
                'my_book_persons' => Relations::OneToManySchema.new(
                  foreign_collection: 'book_person',
                  origin_key: 'book_id',
                  origin_key_target: 'id'
                )
              }
            }
          )

          @collection_book_person = instance_double(
            ForestAdminDatasourceToolkit::Collection,
            name: 'book_person',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'book_id' => ColumnSchema.new(column_type: 'Number'),
                'person_id' => ColumnSchema.new(column_type: 'Number'),
                'my_book' => Relations::ManyToOneSchema.new(
                  foreign_collection: 'book',
                  foreign_key: 'book_id',
                  foreign_key_target: 'id'
                ),
                'my_person' => Relations::ManyToOneSchema.new(
                  foreign_collection: 'person',
                  foreign_key: 'person_id',
                  foreign_key_target: 'id'
                ),
                'date' => ColumnSchema.new(column_type: 'Date')
              }
            }
          )

          @collection_person = instance_double(
            ForestAdminDatasourceToolkit::Collection,
            name: 'person',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'my_book_person' => Relations::OneToOneSchema.new(
                  foreign_collection: 'book_person',
                  origin_key: 'person_id',
                  origin_key_target: 'id'
                )
              }
            }
          )

          @collection_comment = build_collection(
            name: 'comment',
            schema: {
              fields: {
                'id' => build_numeric_primary_key,
                'commentable_id' => build_column(column_type: 'Number'),
                'commentable_type' => build_column,
                'commentable' => Relations::PolymorphicManyToOneSchema.new(
                  foreign_key_type_field: 'commentable_type',
                  foreign_collections: %w[book],
                  foreign_key_targets: { 'book' => 'id' },
                  foreign_key: 'commentable_id'
                )
              }
            }
          )

          datasource.add_collection(@collection_book)
          datasource.add_collection(@collection_book_person)
          datasource.add_collection(@collection_person)
          datasource.add_collection(@collection_comment)

          datasource_decorator = PublicationDatasourceDecorator.new(datasource)

          @decorated_book = datasource_decorator.get_collection('book')
          @decorated_book_person = datasource_decorator.get_collection('book_person')
          @decorated_person = datasource_decorator.get_collection('person')
          @decorated_comment = datasource_decorator.get_collection('comment')
        end

        it 'throws when hiding a field which does not exists' do
          expect { @decorated_person.change_field_visibility('unknown', false) }.to raise_error(ForestException, /No such field 'unknown'/)
        end

        it 'raise when hiding a field referenced in a polymorphic relation' do
          expect do
            @decorated_comment.change_field_visibility('commentable_id', false)
          end.to raise_error(
            ForestException,
            /Cannot remove field 'comment.commentable_id', because it's implied in a polymorphic relation 'comment.commentable'/
          )

          expect do
            @decorated_comment.change_field_visibility('commentable_type', false)
          end.to raise_error(
            ForestException,
            /Cannot remove field 'comment.commentable_type', because it's implied in a polymorphic relation 'comment.commentable'/
          )
        end

        it 'throws when hiding the primary key' do
          expect { @decorated_person.change_field_visibility('id', false) }.to raise_error(ForestException, /Cannot hide primary key/)
        end

        it 'the schema should be the same when doing nothing' do
          expect(@decorated_person.schema).to eq(@collection_person.schema)
          expect(@decorated_book_person.schema).to eq(@collection_book_person.schema)
          expect(@decorated_book.schema).to eq(@collection_book.schema)
        end

        it 'the schema should be the same when hiding and showing fields again' do
          @decorated_person.change_field_visibility('my_book_person', false)
          @decorated_person.change_field_visibility('my_book_person', true)

          expect(@decorated_person.schema).to eq(@collection_person.schema)
        end

        context 'when hiding normal fields' do
          before do
            @decorated_book_person.change_field_visibility('date', false)
          end

          it 'the field should be removed from the schema of the collection' do
            expect(@decorated_book_person.schema[:fields]).not_to have_key('date')
          end

          it 'other fields should not be affected' do
            expect(@decorated_book_person.schema[:fields]).to have_key('book_id')
            expect(@decorated_book_person.schema[:fields]).to have_key('person_id')
            expect(@decorated_book_person.schema[:fields]).to have_key('my_book')
            expect(@decorated_book_person.schema[:fields]).to have_key('my_person')
          end

          it 'other collections should not be affected' do
            expect(@decorated_person.schema).to eq(@collection_person.schema)
            expect(@decorated_book.schema).to eq(@collection_book.schema)
          end

          it 'create should proxies return value (removing extra columns)' do
            created = { 'id' => 1, 'book_id' => 2, 'person_id' => 3, 'date' => '1985-10-26' }
            allow(@collection_book_person).to receive(:create).and_return(created)

            result = @decorated_book_person.create(caller, { 'something' => true })
            expect(result).to eq({ 'id' => 1, 'book_id' => 2, 'person_id' => 3 })
          end
        end

        context 'when hiding foreign keys' do
          before do
            @decorated_book_person.change_field_visibility('book_id', false)
          end

          it 'the fk should be hidden' do
            expect(@decorated_book_person.schema[:fields]).not_to have_key('book_id')
          end

          it 'all linked relations should be removed as well' do
            expect(@decorated_book_person.schema[:fields]).not_to have_key('my_book')
            expect(@decorated_book.schema[:fields]).not_to have_key('my_persons')
            expect(@decorated_book.schema[:fields]).not_to have_key('my_book_persons')
          end

          it 'relations which do not depend on this fk should be left alone' do
            expect(@decorated_book_person.schema[:fields]).to have_key('my_person')
            expect(@decorated_person.schema[:fields]).to have_key('my_book_person')
          end
        end

        context 'when the relations is unknown (type nil)' do
          it 'logs a warning and returns false when the field is not found in the schema' do
            logger = instance_spy(Logger)
            allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)

            result = @decorated_book.published?('unknown_field')

            expect(logger).to have_received(:log).with('Warn', "Field 'unknown_field' not found in schema of collection 'book'")
            expect(result).to be(false)
          end
        end

        context 'when checking bidirectional relations (circular references)' do
          before do
            @collection_user = instance_double(
              ForestAdminDatasourceToolkit::Collection,
              name: 'user',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                  'orders' => Relations::OneToManySchema.new(
                    foreign_collection: 'order',
                    origin_key: 'user_id',
                    origin_key_target: 'id'
                  )
                }
              }
            )

            @collection_order = instance_double(
              ForestAdminDatasourceToolkit::Collection,
              name: 'order',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                  'user_id' => ColumnSchema.new(column_type: 'Number'),
                  'user' => Relations::ManyToOneSchema.new(
                    foreign_collection: 'user',
                    foreign_key: 'user_id',
                    foreign_key_target: 'id'
                  )
                }
              }
            )

            @circular_datasource = ForestAdminDatasourceToolkit::Datasource.new
            @circular_datasource.add_collection(@collection_user)
            @circular_datasource.add_collection(@collection_order)

            @circular_datasource_decorator = PublicationDatasourceDecorator.new(@circular_datasource)
            @decorated_user = @circular_datasource_decorator.get_collection('user')
            @decorated_order = @circular_datasource_decorator.get_collection('order')
          end

          it 'does not cause infinite recursion when checking published on bidirectional relations' do
            # This should not raise SystemStackError (stack level too deep)
            expect { @decorated_user.published?('orders') }.not_to raise_error
            expect { @decorated_order.published?('user') }.not_to raise_error
          end

          it 'returns true for valid bidirectional relations' do
            expect(@decorated_user.published?('orders')).to be(true)
            expect(@decorated_order.published?('user')).to be(true)
          end

          it 'schema includes bidirectional relations without infinite recursion' do
            # This should not raise SystemStackError
            expect { @decorated_user.schema }.not_to raise_error
            expect { @decorated_order.schema }.not_to raise_error

            expect(@decorated_user.schema[:fields]).to have_key('orders')
            expect(@decorated_order.schema[:fields]).to have_key('user')
          end
        end

        context 'when relation has missing foreign key target' do
          before do
            @collection_with_bad_relation = instance_double(
              ForestAdminDatasourceToolkit::Collection,
              name: 'bad_collection',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                  'related' => Relations::ManyToOneSchema.new(
                    foreign_collection: 'person',
                    foreign_key: 'related_id',
                    foreign_key_target: 'missing_field'
                  ),
                  'related_id' => ColumnSchema.new(column_type: 'Number')
                }
              }
            )

            datasource.add_collection(@collection_with_bad_relation)
            datasource_decorator = PublicationDatasourceDecorator.new(datasource)
            @decorated_bad = datasource_decorator.get_collection('bad_collection')
          end

          it 'logs a warning and returns false when foreign_key_target is missing' do
            logger = instance_spy(Logger)
            allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)

            result = @decorated_bad.published?('related')

            expect(logger).to have_received(:log).with(
              'Warn',
              "Field 'missing_field' (foreign_key_target) not found in schema of collection 'person'. " \
              'This relation will be hidden. Check if the field exists in your database.'
            )
            expect(result).to be(false)
          end
        end
      end
    end
  end
end
