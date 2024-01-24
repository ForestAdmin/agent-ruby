require 'spec_helper'

module ForestAdminDatasourceCustomizer
  include ForestAdminDatasourceToolkit
  include ForestAdminDatasourceToolkit::Schema
  include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
  include ForestAdminDatasourceCustomizer::Decorators::Computed
  describe CollectionCustomizer do
    before do
      datasource = Datasource.new
      collection_book = instance_double(
        Collection,
        name: 'book',
        schema: {
          fields: {
            'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
            'title' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::EQUAL]),
            'reference' => ColumnSchema.new(column_type: 'String'),
            'child_id' => ColumnSchema.new(column_type: 'Number', filter_operators: [Operators::EQUAL, Operators::IN]),
            'author_id' => ColumnSchema.new(column_type: 'String', is_read_only: true, is_sortable: true),
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
            'person_id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
            'book_id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
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
            'name' => ColumnSchema.new(column_type: 'String'),
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

      #  $collectionCategory = new Collection($datasource, 'Category');
      #         $collectionCategory->addFields(
      #             [
      #                 'id'    => new ColumnSchema(columnType: PrimitiveType::NUMBER, filterOperators: [Operators::EQUAL, Operators::IN], isPrimaryKey: true),
      #                 'label' => new ColumnSchema(columnType: PrimitiveType::STRING),
      #                 'books' => new OneToManySchema(
      #                     originKey: 'categoryId',
      #                     originKeyTarget: 'id',
      #                     foreignCollection: 'Book',
      #                 ),
      #             ]
      #         );
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

      # TODO: uncomment this test when the relation decorator will be implemented
      # it 'should add a field to late collection' do
      #   stack = @datasource_customizer.stack
      #   allow(stack.late_computed).to receive(:get_collection).with('book').and_return(@datasource_customizer.stack.late_computed.get_collection('book'))
      #
      #   field_definition = ComputedDefinition.new(
      #     column_type: PrimitiveType::STRING,
      #     dependencies: ['id'],
      #     values: proc { |records| records.map { |record| record['id'].to_s + '-Foo' } },
      #   )
      #
      #   customizer = CollectionCustomizer.new(@datasource_customizer, @datasource_customizer.stack, 'book')
      #   # $customizer->addManyToOneRelation('mySelf', 'Book', 'id', 'childId');
      #   customizer.add_field('mySelf', field_definition)
      #   @datasource_customizer.datasource({})
      #
      #   computed_collection = @datasource_customizer.stack.late_computed.get_collection('book')
      #
      #   expect(computed_collection.fields).to have_key('mySelf')
      #   expect(computed_collection.get_computed('mySelf').get_values(data)).to eq(['1-Foo', '2-Foo'])
      # end
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
  end
end
