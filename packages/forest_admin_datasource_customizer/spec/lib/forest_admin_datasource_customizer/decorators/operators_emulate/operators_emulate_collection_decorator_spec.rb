require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module OperatorsEmulate
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Decorators
      include ForestAdminDatasourceToolkit::Schema

      describe OperatorsEmulateCollectionDecorator do
        include_context 'with caller'
        context 'when the collection pk does not supports EQUAL or IN operators' do
          before do
            datasource = Datasource.new
            @child_collection_book = build_collection(
              name: 'book',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(
                    is_primary_key: true,
                    column_type: 'Number',
                    filter_operators: []
                  ),
                  'title' => ColumnSchema.new(column_type: 'String')
                }
              }
            )
            datasource.add_collection(@child_collection_book)

            @datasource_decorator = DatasourceDecorator.new(datasource, described_class)
            @decorated_book = @datasource_decorator.get_collection('book')
          end

          describe 'emulateFieldOperator()' do
            it 'throw on any case' do
              expect do
                @decorated_book.emulate_field_operator('title', Operators::GREATER_THAN)
              end.to raise_error(
                ForestAdminAgent::Http::Exceptions::UnprocessableError,
                'Cannot override operators on collection title: ' \
                "the primary key columns must support 'Equal' and 'In' operators."
              )
            end
          end
        end

        context 'when the collection pk supports EQUAL or IN operators' do
          before do
            datasource = Datasource.new
            @child_collection_book = build_collection(
              name: 'book',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(
                    is_primary_key: true,
                    column_type: 'Number',
                    filter_operators: [Operators::EQUAL, Operators::IN]
                  ),
                  'author_id' => ColumnSchema.new(column_type: 'String'),
                  'author' => Relations::ManyToOneSchema.new(
                    foreign_collection: 'person',
                    foreign_key: 'author_id',
                    foreign_key_target: 'id'
                  ),
                  'title' => ColumnSchema.new(column_type: 'String')
                }
              }
            )
            @child_collection_person = build_collection(
              name: 'person',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(
                    is_primary_key: true,
                    column_type: 'Number',
                    filter_operators: [Operators::EQUAL, Operators::IN]
                  ),
                  'first_name' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::EQUAL]),
                  'last_name' => ColumnSchema.new(column_type: 'String')
                }
              }
            )
            datasource.add_collection(@child_collection_book)
            datasource.add_collection(@child_collection_person)

            @datasource_decorator = DatasourceDecorator.new(datasource, described_class)
            @decorated_book = @datasource_decorator.get_collection('book')
            @decorated_person = @datasource_decorator.get_collection('person')
          end

          describe 'emulateFieldOperator()' do
            it 'raise if the field does not exists' do
              expect do
                @decorated_book.emulate_field_operator('__dontExist', Operators::EQUAL)
              end.to raise_error(Exceptions::ValidationError, "Column not found: 'book.__dontExist'")
            end

            it 'raise if the field is a relation' do
              expect do
                @decorated_book.emulate_field_operator('author', Operators::EQUAL)
              end.to raise_error(
                Exceptions::ValidationError,
                "Unexpected field type: 'book.author' (found 'ManyToOne' expected 'Column')"
              )
            end

            it 'raise if the field is in a relation' do
              expect do
                @decorated_book.emulate_field_operator('author:first_name', Operators::EQUAL)
              end.to raise_error(ForestAdminAgent::Http::Exceptions::UnprocessableError, 'Cannot replace operator for relation')
            end

            describe 'when implementing an operator from an unsupported one' do
              before do
                @decorated_book.replace_field_operator('title', Operators::STARTS_WITH) do
                  { field: 'title', operator: Operators::LIKE, value: 'aTitleValue' }
                end
              end

              it 'raise when call list' do
                projection = Projection.new(%w[id title])
                filter = Filter.new(condition_tree: Nodes::ConditionTreeLeaf.new('title', Operators::STARTS_WITH, 'found'))

                expect do
                  @decorated_book.list(caller, filter, projection)
                end.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ValidationError, "The given operator 'like' is not supported by the column: 'title'. The column is not filterable")
              end
            end

            describe 'when creating a cycle in the replacements graph' do
              before do
                @decorated_book.replace_field_operator('title', Operators::STARTS_WITH) do |value|
                  { field: 'title', operator: Operators::LIKE, value: "#{value}%" }
                end

                @decorated_book.replace_field_operator('title', Operators::LIKE) do |value|
                  { field: 'title', operator: Operators::STARTS_WITH, value: "#{value}%" }
                end
              end

              it 'raise when call list' do
                projection = Projection.new(%w[id title])
                filter = Filter.new(condition_tree: Nodes::ConditionTreeLeaf.new('title', Operators::STARTS_WITH, 'found'))

                expect do
                  @decorated_book.list(caller, filter, projection)
                end.to raise_error(ForestAdminAgent::Http::Exceptions::UnprocessableError, 'Operator replacement cycle: book.title[starts_with] -> book.title[like]')
              end
            end

            describe 'when emulating an operator' do
              before do
                @decorated_person.emulate_field_operator('first_name', Operators::STARTS_WITH)
              end

              it 'schema() support start_with operator' do
                field = @decorated_person.schema[:fields]['first_name']
                expect(field.filter_operators).to eq([Operators::EQUAL, Operators::STARTS_WITH])
              end

              it 'list() should not rewrite the condition tree with another operator' do
                allow(@child_collection_book).to receive(:list).and_return([{ id: 2, title: 'Foundation' }])
                projection = Projection.new(%w[id title])
                filter = Filter.new(condition_tree: Nodes::ConditionTreeLeaf.new('author:first_name', Operators::EQUAL, 'Isaac'))
                records = @decorated_book.list(caller, filter, projection)

                expect(records).to eq([{ id: 2, title: 'Foundation' }])
                expect(@child_collection_book).to have_received(:list) do |_caller, list_filter, _projection|
                  expect(list_filter.condition_tree.to_h).to eq(
                    { field: 'author:first_name', operator: Operators::EQUAL, value: 'Isaac' }
                  )
                end
              end

              it 'list() should find books from author:firstname prefix' do
                allow(@child_collection_book).to receive(:list).and_return([{ 'id' => 2, 'title' => 'Foundation' }])
                allow(@child_collection_person).to receive(:list).and_return(
                  [
                    { 'id' => 1, 'first_name' => 'Edward' },
                    { 'id' => 2, 'first_name' => 'Isaac' }
                  ]
                )
                projection = Projection.new(%w[id title])
                filter = Filter.new(condition_tree: Nodes::ConditionTreeLeaf.new('author:first_name', Operators::STARTS_WITH, 'Isaa'))
                records = @decorated_book.list(caller, filter, projection)

                expect(records).to eq([{ 'id' => 2, 'title' => 'Foundation' }])
                expect(@child_collection_person).to have_received(:list) do |_caller, _filter, list_projection|
                  expect(list_projection.to_a).to eq(%w[first_name id])
                end
                expect(@child_collection_book).to have_received(:list) do |_caller, list_filter, _projection|
                  expect(list_filter.condition_tree.to_h).to eq(
                    { field: 'author:id', operator: Operators::EQUAL, value: 2 }
                  )
                end
              end
            end
          end
        end
      end
    end
  end
end
