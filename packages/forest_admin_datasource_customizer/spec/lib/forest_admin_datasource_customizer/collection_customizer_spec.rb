require 'spec_helper'
require 'shared/caller'

module ForestAdminDatasourceCustomizer
  include ForestAdminDatasourceToolkit
  include ForestAdminDatasourceToolkit::Schema
  include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
  include ForestAdminDatasourceCustomizer::Decorators::Computed
  include ForestAdminDatasourceCustomizer::Decorators::Action
  include ForestAdminDatasourceCustomizer::Context
  describe CollectionCustomizer do
    include_context 'with caller'
    before do
      datasource = Datasource.new
      collection_book = instance_double(
        Collection,
        name: 'book',
        schema: {
          fields: {
            'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::EQUAL, Operators::IN]),
            'title' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::EQUAL]),
            'reference' => ColumnSchema.new(column_type: 'String'),
            'child_id' => ColumnSchema.new(column_type: 'Number', filter_operators: [Operators::EQUAL, Operators::IN]),
            'author_id' => ColumnSchema.new(column_type: 'Number', is_read_only: true, is_sortable: true, filter_operators: [Operators::EQUAL, Operators::IN]),
            'author' => Relations::ManyToOneSchema.new(
              foreign_key: 'author_id',
              foreign_collection: 'person',
              foreign_key_target: 'id'
            ),
            'persons' => Relations::ManyToManySchema.new(
              origin_key: 'book_id',
              origin_key_target: 'id',
              foreign_key: 'person_id',
              foreign_key_target: 'id',
              foreign_collection: 'person',
              through_collection: 'book_person'
            )
          }
        }
      )

      collection_book_person = instance_double(
        Collection,
        name: 'book_person',
        schema: {
          fields: {
            'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::EQUAL, Operators::IN]),
            'person_id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::EQUAL, Operators::IN]),
            'book_id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::EQUAL, Operators::IN]),
            'category' => Relations::ManyToOneSchema.new(
              foreign_key: 'category_id',
              foreign_key_target: 'id',
              foreign_collection: 'category'
            ),
            'person' => Relations::ManyToOneSchema.new(
              foreign_key: 'person_id',
              foreign_key_target: 'id',
              foreign_collection: 'person'
            )
          }
        }
      )

      collection_person = instance_double(
        Collection,
        name: 'person',
        schema: {
          fields: {
            'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::EQUAL, Operators::IN]),
            'name' => ColumnSchema.new(column_type: 'String', is_sortable: true),
            'name_in_read_only' => ColumnSchema.new(column_type: 'String', is_read_only: true),
            'book' => Relations::OneToOneSchema.new(
              origin_key: 'author_id',
              origin_key_target: 'id',
              foreign_collection: 'book'
            ),
            'books' => Relations::ManyToManySchema.new(
              origin_key: 'person_id',
              origin_key_target: 'id',
              foreign_key: 'book_id',
              foreign_key_target: 'id',
              foreign_collection: 'book',
              through_collection: 'book_person'
            )
          }
        }
      )

      collection_category = instance_double(
        Collection,
        name: 'category',
        schema: {
          fields: {
            'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::EQUAL, Operators::IN]),
            'label' => ColumnSchema.new(column_type: 'String'),
            'books' => Relations::OneToManySchema.new(
              origin_key: 'category_id',
              origin_key_target: 'id',
              foreign_collection: 'book'
            )
          }
        }
      )

      datasource.add_collection(collection_book)
      datasource.add_collection(collection_book_person)
      datasource.add_collection(collection_person)
      datasource.add_collection(collection_category)

      @datasource_customizer = DatasourceCustomizer.new
      @datasource_customizer.add_datasource(datasource, {})
    end

    context 'when using add_action' do
      it 'adds an action to early collection' do
        stack = @datasource_customizer.stack
        stack.apply_queued_customizations({})
        allow(stack.action).to receive(:get_collection).with('book').and_return(@datasource_customizer.stack.action.get_collection('book'))

        action = BaseAction.new(scope: Types::ActionScope::SINGLE) do |_context, result_builder|
          result_builder.success
        end

        customizer = described_class.new(@datasource_customizer, @datasource_customizer.stack, 'book')
        customizer.add_action('my_action', action)
        action_collection = @datasource_customizer.stack.action.get_collection('book')
        stack.apply_queued_customizations({})

        expect(action_collection.actions).to have_key('my_action')
        expect(action_collection.actions['my_action']).to eq(action)
      end
    end

    context 'when using add_field' do
      let(:data) do
        [
          { 'id' => 1, 'title' => 'Foundation' },
          { 'id' => 2, 'title' => 'Harry Potter' }
        ]
      end

      it 'adds a field to early collection' do
        stack = @datasource_customizer.stack
        allow(stack.early_computed).to receive(:get_collection).with('book').and_return(@datasource_customizer.stack.early_computed.get_collection('book'))

        field_definition = ComputedDefinition.new(
          column_type: PrimitiveType::STRING,
          dependencies: ['title'],
          values: proc { |records| records.map { |record| "#{record["title"]}-2022" } }
        )

        customizer = described_class.new(@datasource_customizer, @datasource_customizer.stack, 'book')
        customizer.add_field('test', field_definition)
        @datasource_customizer.datasource({})

        computed_collection = @datasource_customizer.stack.early_computed.get_collection('book')

        expect(computed_collection.fields).to have_key('test')
        expect(computed_collection.get_computed('test').get_values(data)).to eq(['Foundation-2022', 'Harry Potter-2022'])
      end

      it 'adds a field to late collection' do
        stack = @datasource_customizer.stack
        allow(stack.late_computed).to receive(:get_collection).with('book').and_return(@datasource_customizer.stack.early_computed.get_collection('book'))

        field_definition = ComputedDefinition.new(
          column_type: PrimitiveType::STRING,
          dependencies: ['id'],
          values: proc { |records| records.map { |record| "#{record["id"]}-Foo" } }
        )

        customizer = described_class.new(@datasource_customizer, @datasource_customizer.stack, 'book')
        customizer.add_many_to_one_relation('mySelf', 'book', { foreign_key: 'id', foreign_key_target: 'child_id' })
        customizer.add_field('mySelf', field_definition)
        @datasource_customizer.datasource({})

        computed_collection = @datasource_customizer.stack.late_computed.get_collection('book')

        expect(computed_collection.fields).to have_key('mySelf')
        expect(computed_collection.get_computed('mySelf').get_values(data)).to eq(['1-Foo', '2-Foo'])
      end
    end

    context 'when using replace_search' do
      it 'calls the search decorator' do
        stack = @datasource_customizer.stack
        allow(stack.search).to receive(:get_collection).with('book').and_return(@datasource_customizer.stack.search.get_collection('book'))

        condition = proc { |search| [{ field: 'title', operator: Operators::EQUAL, value: search }] }

        customizer = described_class.new(@datasource_customizer, @datasource_customizer.stack, 'book')
        customizer.replace_search(condition)
        @datasource_customizer.datasource({})

        search_collection = @datasource_customizer.stack.search.get_collection('book')

        expect(search_collection.instance_variable_get(:@replacer)).to eq(condition)
      end
    end

    context 'when using disable_count' do
      it 'disables count on the collection' do
        customizer = described_class.new(@datasource_customizer, @datasource_customizer.stack, 'book')
        customizer.disable_count
        @datasource_customizer.datasource([])

        expect(@datasource_customizer.stack.schema.get_collection('book').schema[:countable]).to be false
      end
    end

    context 'when adding a relation' do
      it 'adds a many to one' do
        customizer = described_class.new(@datasource_customizer, @datasource_customizer.stack, 'book')
        customizer.add_many_to_one_relation('myAuthor', 'person', { foreign_key: 'author_id' })
        @datasource_customizer.datasource({})

        relation_collection = @datasource_customizer.stack.relation.get_collection('book')

        expect(relation_collection.relations).to have_key('myAuthor')
        expect(relation_collection.relations['myAuthor']).to be_a(Relations::ManyToOneSchema)
        expect(relation_collection.relations['myAuthor'].foreign_collection).to eq('person')
        expect(relation_collection.relations['myAuthor'].foreign_key).to eq('author_id')
        expect(relation_collection.relations['myAuthor'].foreign_key_target).to eq('id')
      end

      it 'adds a one to one' do
        customizer = described_class.new(@datasource_customizer, @datasource_customizer.stack, 'person')
        customizer.add_one_to_one_relation('myBookAuthor', 'book_person', { origin_key: 'person_id', origin_key_target: 'id' })
        @datasource_customizer.datasource({})

        relation_collection = @datasource_customizer.stack.relation.get_collection('person')

        expect(relation_collection.relations).to have_key('myBookAuthor')
        expect(relation_collection.relations['myBookAuthor']).to be_a(Relations::OneToOneSchema)
        expect(relation_collection.relations['myBookAuthor'].foreign_collection).to eq('book_person')
        expect(relation_collection.relations['myBookAuthor'].origin_key).to eq('person_id')
        expect(relation_collection.relations['myBookAuthor'].origin_key_target).to eq('id')
      end

      it 'adds a one to many' do
        customizer = described_class.new(@datasource_customizer, @datasource_customizer.stack, 'person')
        customizer.add_one_to_many_relation('myBookAuthors', 'book_person', { origin_key: 'person_id', origin_key_target: 'id' })
        @datasource_customizer.datasource({})

        relation_collection = @datasource_customizer.stack.relation.get_collection('person')

        expect(relation_collection.relations).to have_key('myBookAuthors')
        expect(relation_collection.relations['myBookAuthors']).to be_a(Relations::OneToManySchema)
        expect(relation_collection.relations['myBookAuthors'].foreign_collection).to eq('book_person')
        expect(relation_collection.relations['myBookAuthors'].origin_key).to eq('person_id')
        expect(relation_collection.relations['myBookAuthors'].origin_key_target).to eq('id')
      end

      it 'adds a many to many' do
        customizer = described_class.new(@datasource_customizer, @datasource_customizer.stack, 'person')
        customizer.add_many_to_many_relation('myBooks', 'book', 'book_person', { foreign_key: 'book_id', foreign_key_target: 'id', origin_key: 'person_id', origin_key_target: 'id' })
        @datasource_customizer.datasource({})

        relation_collection = @datasource_customizer.stack.relation.get_collection('person')

        expect(relation_collection.relations).to have_key('myBooks')
        expect(relation_collection.relations['myBooks']).to be_a(Relations::ManyToManySchema)
        expect(relation_collection.relations['myBooks'].foreign_collection).to eq('book')
        expect(relation_collection.relations['myBooks'].through_collection).to eq('book_person')
        expect(relation_collection.relations['myBooks'].foreign_key).to eq('book_id')
        expect(relation_collection.relations['myBooks'].foreign_key_target).to eq('id')
        expect(relation_collection.relations['myBooks'].origin_key).to eq('person_id')
        expect(relation_collection.relations['myBooks'].origin_key_target).to eq('id')
      end

      it 'does not allow replaceFieldSorting' do
        customizer = described_class.new(@datasource_customizer, @datasource_customizer.stack, 'person')
        customizer.add_one_to_one_relation('myBookAuthor', 'book_person', { origin_key: 'person_id', origin_key_target: 'id' })
        customizer.replace_field_sorting('myBookAuthor', [])

        expect { @datasource_customizer.datasource({}) }.to raise_error(Exceptions::ValidationError, "🌳🌳🌳 Unexpected field type: 'person.myBookAuthor' (found 'OneToOne' expected 'Column')")
      end
    end

    context 'when adding external relation' do
      it 'calls addField' do
        data = [{ 'id' => 1, 'title' => 'Dune' }]
        stack = @datasource_customizer.stack
        allow(stack.late_computed).to receive(:get_collection).with('book').and_return(@datasource_customizer.stack.early_computed.get_collection('book'))

        customizer = described_class.new(@datasource_customizer, @datasource_customizer.stack, 'book')
        customizer.add_external_relation(
          'tags',
          {
            schema: ['etag' => 'String', 'selfLink' => 'String'],
            listRecords: proc {
              [
                { 'etag' => 'OTD2tB19qn4', 'selfLink' => 'https://www.googleapis.com/books/v1/volumes/_ojXNuzgHRcC' },
                { 'etag' => 'NsxMT6kCCVs', 'selfLink' => 'https://www.googleapis.com/books/v1/volumes/RJxWIQOvoZUC' }
              ]
            }
          }
        )
        @datasource_customizer.datasource({})

        computed_collection = @datasource_customizer.stack.late_computed.get_collection('book')

        expect(computed_collection.fields).to have_key('tags')
        expect(computed_collection.get_computed('tags').get_values(data, CollectionCustomizationContext.new(computed_collection, caller))).to eq([
                                                                                                                                                   [
                                                                                                                                                     { 'etag' => 'OTD2tB19qn4', 'selfLink' => 'https://www.googleapis.com/books/v1/volumes/_ojXNuzgHRcC' },
                                                                                                                                                     { 'etag' => 'NsxMT6kCCVs', 'selfLink' => 'https://www.googleapis.com/books/v1/volumes/RJxWIQOvoZUC' }
                                                                                                                                                   ]
                                                                                                                                                 ])
      end

      it 'throwns an exception when the plugin have options keys missing' do
        customizer = described_class.new(@datasource_customizer, @datasource_customizer.stack, 'book')
        customizer.add_external_relation('tags', {})
        expect { @datasource_customizer.datasource({}) }.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, '🌳🌳🌳 The options parameter must contains the following keys: `name, schema, listRecords`')
      end
    end

    context 'when adding a field validation' do
      it 'adds a validation rule' do
        stack = @datasource_customizer.stack
        allow(stack.validation).to receive(:get_collection).with('book').and_return(@datasource_customizer.stack.validation.get_collection('book'))

        customizer = described_class.new(@datasource_customizer, @datasource_customizer.stack, 'book')
        customizer.add_field_validation('title', Operators::LONGER_THAN, 5)
        @datasource_customizer.datasource({})

        validation_collection = @datasource_customizer.stack.validation.get_collection('book')

        expect(validation_collection.validation).to have_key('title')
        expect(validation_collection.validation['title']).to eq([{ operator: Operators::LONGER_THAN, value: 5 }])
      end
    end

    context 'when using emulate_field_operator' do
      it 'emulate operator on field' do
        stack = @datasource_customizer.stack
        allow(stack.early_op_emulate).to receive(:get_collection).with('book').and_return(@datasource_customizer.stack.early_op_emulate.get_collection('book'))

        customizer = described_class.new(@datasource_customizer, @datasource_customizer.stack, 'book')
        customizer.emulate_field_operator('title', Operators::PRESENT)
        @datasource_customizer.datasource({})
        op_emulate_collection = @datasource_customizer.stack.early_op_emulate.get_collection('book')

        expect(op_emulate_collection.fields).to have_key('title')
        expect(op_emulate_collection.fields['title']).to eq({ Operators::PRESENT => nil })
      end
    end

    context 'when using replace_field_operator' do
      it 'replace operator on field' do
        stack = @datasource_customizer.stack
        allow(stack.early_op_emulate).to receive(:get_collection).with('book').and_return(@datasource_customizer.stack.early_op_emulate.get_collection('book'))

        customizer = described_class.new(@datasource_customizer, @datasource_customizer.stack, 'book')
        replacer = proc { { field: 'first_name', operator: Operators::NOT_EQUAL, value: nil } }
        customizer.replace_field_operator('title', Operators::PRESENT, &replacer)
        @datasource_customizer.datasource({})
        op_emulate_collection = @datasource_customizer.stack.early_op_emulate.get_collection('book')

        expect(op_emulate_collection.fields).to have_key('title')
        expect(op_emulate_collection.fields['title']).to eq({ Operators::PRESENT => replacer })
      end
    end

    context 'when using emulate_field_sorting' do
      it 'emulate sort on field' do
        stack = @datasource_customizer.stack
        allow(stack.sort).to receive(:get_collection).with('person').and_return(@datasource_customizer.stack.sort.get_collection('person'))

        customizer = described_class.new(@datasource_customizer, @datasource_customizer.stack, 'person')
        customizer.emulate_field_sorting('name')
        @datasource_customizer.datasource({})

        sort_collection = @datasource_customizer.stack.sort.get_collection('person')

        expect(sort_collection.sorts).to have_key('name')
        expect(sort_collection.emulated?('name')).to be_nil
      end
    end

    context 'when using replace_field_sorting' do
      it 'replace sort on field' do
        stack = @datasource_customizer.stack
        allow(stack.sort).to receive(:get_collection).with('person').and_return(@datasource_customizer.stack.sort.get_collection('person'))

        customizer = described_class.new(@datasource_customizer, @datasource_customizer.stack, 'person')
        sort_clauses = [{ field: 'name', ascending: true }]
        customizer.replace_field_sorting('name', sort_clauses)
        @datasource_customizer.datasource({})

        sort_collection = @datasource_customizer.stack.sort.get_collection('person')

        expect(sort_collection.sorts).to have_key('name')
        expect(sort_collection.sorts['name']).to eq(ForestAdminDatasourceToolkit::Components::Query::Sort.new(sort_clauses))
      end
    end

    context 'when using removeField' do
      it 'removes the given fields' do
        customizer = described_class.new(@datasource_customizer, @datasource_customizer.stack, 'person')
        customizer.remove_field('name', 'name_in_read_only')
        @datasource_customizer.datasource({})

        publication_collection = @datasource_customizer.stack.publication.get_collection('person')

        expect(publication_collection.fields).not_to have_key('name')
        expect(publication_collection.fields).not_to have_key('name_in_read_only')
      end
    end
  end
end
