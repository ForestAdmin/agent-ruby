require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module RenameField
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Decorators
      include ForestAdminDatasourceToolkit::Schema

      describe RenameFieldCollectionDecorator do
        include_context 'with caller'
        subject(:rename_field_collection_decorator) { described_class }
        let(:category) { @datasource_decorator.get_collection('category') }

        let(:filter) do
          Filter.new(
            condition_tree: Nodes::ConditionTreeBranch.new(
              'And',
              [
                Nodes::ConditionTreeLeaf.new('id', Operators::NOT_EQUAL, 0),
                Nodes::ConditionTreeLeaf.new('my_book_person:date', Operators::NOT_EQUAL, 0)
              ]
            )
          )
        end

        before do
          datasource = Datasource.new
          @collection_person = build_collection(
            name: 'person',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                         filter_operators: [Operators::EQUAL, Operators::IN]),
                'my_book_person' => Relations::OneToOneSchema.new(
                  foreign_collection: 'book_person',
                  origin_key: 'person_id',
                  origin_key_target: 'id'
                )
              }
            }
          )

          @collection_book_person = build_collection(
            name: 'book_person',
            schema: {
              fields: {
                'book_id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                              filter_operators: [Operators::EQUAL, Operators::IN]),
                'person_id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                                filter_operators: [Operators::EQUAL, Operators::IN]),
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
                'date' => ColumnSchema.new(column_type: 'date')
              }
            }
          )

          @collection_book = build_collection(
            name: 'book',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                         filter_operators: [Operators::EQUAL, Operators::IN]),
                'my_persons' => Relations::ManyToManySchema.new(
                  foreign_collection: 'person',
                  foreign_key: 'person_id',
                  foreign_key_target: 'id',
                  origin_key: 'book_id',
                  origin_key_target: 'id',
                  through_collection: 'book_person'
                ),
                'my_person' => Relations::OneToManySchema.new(
                  foreign_collection: 'book_person',
                  origin_key_target: 'id',
                  origin_key: 'book_id'
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

          datasource.add_collection(@collection_person)
          datasource.add_collection(@collection_book_person)
          datasource.add_collection(@collection_book)
          datasource.add_collection(@collection_comment)

          @datasource_decorator = DatasourceDecorator.new(datasource, rename_field_collection_decorator)
          @new_person = @datasource_decorator.get_collection('person')
          @new_book = @datasource_decorator.get_collection('book')
          @new_book_person = @datasource_decorator.get_collection('book_person')
          @new_comment = @datasource_decorator.get_collection('comment')
        end

        it 'raise an error when renaming a field which does not exists' do
          expect do
            @new_person.rename_field('unknown', 'somethingnew')
          end.to raise_error(Exceptions::ForestException, "🌳🌳🌳 No such field 'unknown'")
        end

        it 'raise if renaming a field referenced in a polymorphic relation' do
          expect do
            @new_comment.rename_field('commentable_id', 'somethingnew')
          end.to raise_error(
            Exceptions::ForestException,
            "🌳🌳🌳 Cannot rename 'comment.commentable_id', because it's implied in a polymorphic relation 'comment.commentable'"
          )

          expect do
            @new_comment.rename_field('commentable_type', 'somethingnew')
          end.to raise_error(
            Exceptions::ForestException,
            "🌳🌳🌳 Cannot rename 'comment.commentable_type', because it's implied in a polymorphic relation 'comment.commentable'"
          )
        end

        it 'raise an error when renaming a field using an older name' do
          @new_person.rename_field('id', 'key')

          expect do
            @new_person.rename_field('id', 'primaryKey')
          end.to raise_error(Exceptions::ForestException, "🌳🌳🌳 No such field 'id'")
        end

        it 'raise an error when renaming with a name including space' do
          expect do
            @new_person.rename_field('id', 'the key')
          end.to raise_error(Exceptions::ValidationError)
        end

        it 'allow renaming multiple times the same field' do
          @new_person.rename_field('id', 'key')
          @new_person.rename_field('key', 'primary_key')
          @new_person.rename_field('primary_key', 'primary_id')
          @new_person.rename_field('primary_id', 'id')

          expect(@new_person.schema).to eq(@collection_person.schema)
        end

        describe 'when not renaming anything' do
          it 'return the same schemas' do
            expect(@new_person.schema).to eq(@collection_person.schema)
            expect(@new_book.schema).to eq(@collection_book.schema)
            expect(@new_book_person.schema).to eq(@collection_book_person.schema)
          end

          it 'act as a pass-through when call create()' do
            allow(@collection_person).to receive(:create).and_return({ 'id' => 1 })
            record = @new_person.create(caller, { 'id' => 1 })

            expect(@collection_person).to have_received(:create)
            expect(record).to eq({ 'id' => 1 })
          end

          it 'act as a pass-through when call list()' do
            records = [{ 'id' => '1', 'my_book_person' => { 'date' => 'something' } }]
            projection = Projection.new(%w[id my_book_person:date])

            allow(@collection_person).to receive(:list).and_return(records)

            result = @new_person.list(caller, filter, projection)

            expect(@collection_person).to have_received(:list)
            expect(result).to eq(records)
          end

          it 'act as a pass-through when call list() on collection with a polymorphic relation' do
            records = [{ 'id' => '1', 'commentable' => { 'id' => '1' } }]
            projection = Projection.new(%w[id commentable:*])
            allow(@collection_comment).to receive(:list).and_return(records)

            result = @new_comment.list(caller, filter, projection)

            expect(@collection_comment).to have_received(:list) do |_caller, _filter, child_projection|
              expect(child_projection).to match_array(projection)
            end
            expect(result).to eq(records)
          end

          it 'act as a pass-through when call update()' do
            allow(@collection_person).to receive(:update)
            @new_person.update(caller, filter, { 'id' => 55 })

            expect(@collection_person).to have_received(:update) do |_caller, _filter, patch|
              expect(patch).to eq({ 'id' => 55 })
            end
          end

          it 'act as a pass-through when call delete()' do
            allow(@collection_person).to receive(:delete)
            @new_person.delete(caller, filter)

            expect(@collection_person).to have_received(:delete)
          end

          it 'act as a pass-through when call aggregate()' do
            result = [{ 'value' => 34, 'group' => { 'my_book_person:date' => 'abc' } }]
            aggregate = Aggregation.new(operation: 'Count')
            allow(@collection_person).to receive(:aggregate).and_return(result)

            rows = @new_person.aggregate(caller, filter, aggregate)

            expect(@collection_person).to have_received(:aggregate)
            expect(rows).to eq(result)
          end
        end

        describe 'when renaming columns and relations' do
          let(:new_person_filter) do
            Filter.new(
              condition_tree: Nodes::ConditionTreeBranch.new(
                'And',
                [
                  Nodes::ConditionTreeLeaf.new('primary_key', Operators::NOT_EQUAL, 0),
                  Nodes::ConditionTreeLeaf.new('my_novel_author:created_at', Operators::NOT_EQUAL, 0)
                ]
              )
            )
          end

          before do
            @new_person.rename_field('id', 'primary_key')
            @new_person.rename_field('my_book_person', 'my_novel_author')
            @new_book_person.rename_field('date', 'created_at')
          end

          it 'return the schemas updated' do
            expect(@new_person.schema[:fields].keys).to eq(%w[primary_key my_novel_author])
          end

          it 'rewrite the records when call create' do
            allow(@collection_person).to receive(:create).and_return({ 'id' => 1 })
            record = @new_person.create(caller, { 'primary_key' => 1 })

            expect(@collection_person).to have_received(:create) do |_caller, data|
              expect(data).to eq({ 'id' => 1 })
            end
            expect(record).to eq({ 'primary_key' => 1 })
          end

          it 'rewrite the filter, projection and record when call list()' do
            projection = Projection.new(%w[primary_key my_novel_author:created_at])

            allow(@collection_person).to receive(:list).and_return(
              [{ 'id' => '1', 'my_book_person' => { 'date' => 'something' } }]
            )

            result = @new_person.list(caller, new_person_filter, projection)

            expect(@collection_person).to have_received(:list) do |_caller, _filter, base_projection|
              expect(base_projection.to_a).to eq(%w[id my_book_person:date])
            end
            expect(result).to eq([{ 'primary_key' => '1', 'my_novel_author' => { 'created_at' => 'something' } }])
          end

          it 'rewrite the record with null relations when call list()' do
            projection = Projection.new(%w[primary_key my_novel_author:created_at])

            allow(@collection_person).to receive(:list).and_return(
              [{ 'id' => '1', 'my_book_person' => nil }]
            )

            result = @new_person.list(caller, new_person_filter, projection)
            expect(result).to eq([{ 'primary_key' => '1', 'my_novel_author' => nil }])
          end

          it 'rewrite the filter and patch when call update()' do
            allow(@collection_person).to receive(:update)
            @new_person.update(caller, new_person_filter, { 'primary_key' => 55 })

            expect(@collection_person).to have_received(:update) do |_caller, _filter, patch|
              expect(patch).to eq({ 'id' => 55 })
            end
          end

          it 'act as a pass-through when call delete()' do
            allow(@collection_person).to receive(:delete)
            @new_person.delete(caller, new_person_filter)

            expect(@collection_person).to have_received(:delete) do |_caller, filter|
              expect(filter.condition_tree.to_h).to eq(
                Nodes::ConditionTreeBranch.new(
                  'And',
                  [
                    Nodes::ConditionTreeLeaf.new('id', Operators::NOT_EQUAL, 0),
                    Nodes::ConditionTreeLeaf.new('my_book_person:date', Operators::NOT_EQUAL, 0)
                  ]
                ).to_h
              )
            end
          end

          it 'act as a pass-through when call aggregate()' do
            result = [{ 'value' => 34, 'group' => { 'my_book_person:date' => 'abc' } }]
            aggregate = Aggregation.new(
              operation: 'Sum',
              field: 'primary_key',
              groups: [{ field: 'my_novel_author:created_at' }]
            )
            allow(@collection_person).to receive(:aggregate).and_return(result)
            rows = @new_person.aggregate(caller, new_person_filter, aggregate)

            expect(@collection_person).to have_received(:aggregate)
            expect(rows).to eq([{ 'value' => 34, 'group' => { 'my_novel_author:created_at' => 'abc' } }])
          end
        end

        describe 'when renaming foreign keys' do
          before do
            @new_book_person.rename_field('book_id', 'novel_id')
            @new_book_person.rename_field('person_id', 'author_id')
          end

          it 'the columns should be renamed in the schema' do
            fields = @new_book_person.schema[:fields]
            expect(fields['author_id']).to be_a(ColumnSchema)
            expect(fields['novel_id']).to be_a(ColumnSchema)
            expect(fields['person_id']).to be_nil
            expect(fields['book_id']).to be_nil
          end

          it 'the relations should be updated in all collections' do
            book_fields = @new_book.schema[:fields]
            book_person_fields = @new_book_person.schema[:fields]
            person_fields = @new_person.schema[:fields]

            expect(book_fields['my_persons'].foreign_key).to eq('author_id')
            expect(book_fields['my_persons'].origin_key).to eq('novel_id')
            expect(book_person_fields['my_book'].foreign_key).to eq('novel_id')
            expect(book_person_fields['my_person'].foreign_key).to eq('author_id')
            expect(person_fields['my_book_person'].origin_key).to eq('author_id')
          end
        end

        describe 'when renaming primary keys' do
          it 'the relations should be updated in all collections' do
            @new_book.rename_field('id', 'new_book_id')
            @new_person.rename_field('id', 'new_person_id')

            book_fields = @new_book.schema[:fields]
            book_person_fields = @new_book_person.schema[:fields]
            person_fields = @new_person.schema[:fields]

            expect(book_fields['my_persons'].origin_key_target).to eq('new_book_id')
            expect(book_fields['my_persons'].foreign_key_target).to eq('new_person_id')
            expect(book_person_fields['my_book'].foreign_key_target).to eq('new_book_id')
            expect(book_person_fields['my_person'].foreign_key_target).to eq('new_person_id')
            expect(person_fields['my_book_person'].origin_key_target).to eq('new_person_id')
          end
        end
      end
    end
  end
end
