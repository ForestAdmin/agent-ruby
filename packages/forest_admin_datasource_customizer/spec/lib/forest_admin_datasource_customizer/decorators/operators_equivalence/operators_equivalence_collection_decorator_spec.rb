require 'spec_helper'
require 'shared/caller'

module ForestAdminDatasourceCustomizer
  module Decorators
    module OperatorsEquivalence
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Decorators
      include ForestAdminDatasourceToolkit::Schema

      describe OperatorsEquivalenceCollectionDecorator do
        include_context 'with caller'
        subject(:operators_equivalence_collection_decorator) { described_class }

        let(:decorated_book) { @datasource_decorator.get_collection('book') }
        let(:aggregation) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Aggregation) }

        before do
          datasource = Datasource.new
          @child_collection_book = build_collection(
            name: 'book',
            schema: {
              fields: {
                'col' => ColumnSchema.new(
                  column_type: 'Date',
                  filter_operators: [Operators::LESS_THAN, Operators::EQUAL, Operators::GREATER_THAN]
                ),
                'rel' => Relations::ManyToOneSchema.new(
                  foreign_collection: 'author',
                  foreign_key: 'col',
                  foreign_key_target: 'id'
                )
              }
            }
          )
          datasource.add_collection(@child_collection_book)

          @datasource_decorator = DatasourceDecorator.new(datasource, operators_equivalence_collection_decorator)
        end

        context 'with a date field which support only "<", "==" and ">"' do
          it 'schema should support more operators' do
            schema = @datasource_decorator.get_collection('book').schema[:fields]['col']

            expect(schema.filter_operators.size).to be > 20
          end

          it 'schema should not have dropped relations' do
            schema = @datasource_decorator.get_collection('book').schema

            expect(schema[:fields].keys).to eq(%w[col rel])
          end

          it 'list() should work with a null condition tree' do
            allow(@child_collection_book).to receive(:list).and_return([])
            decorated_book.list(
              caller,
              Filter.new,
              Projection.new
            )

            expect(@child_collection_book).to have_received(:list)
          end

          it 'list() should not modify supported operators' do
            tree = Nodes::ConditionTreeLeaf.new('col', Operators::EQUAL, 'someData')
            allow(@child_collection_book).to receive(:list).and_return([])
            decorated_book.list(
              caller,
              Filter.new(condition_tree: tree),
              Projection.new(['col'])
            )

            expect(@child_collection_book).to have_received(:list) do |context_caller, filter, projection|
              expect(context_caller).to eq caller
              expect(filter.condition_tree).to eq tree
              expect(projection).to eq Projection.new(['col'])
            end
          end

          it 'list() should transform "In -> Equal"' do
            tree = Nodes::ConditionTreeLeaf.new('col', Operators::IN, ['someData'])
            allow(@child_collection_book).to receive(:list).and_return([])
            decorated_book.list(
              caller,
              Filter.new(condition_tree: tree),
              Projection.new(['col'])
            )

            expect(@child_collection_book).to have_received(:list) do |context_caller, filter, projection|
              expect(context_caller).to eq caller
              expect(filter.condition_tree.to_h).to include(field: 'col', operator: Operators::EQUAL, value: 'someData')
              expect(projection).to eq Projection.new(['col'])
            end
          end

          it 'list() should transform "Blank -> In -> Equal"' do
            tree = Nodes::ConditionTreeLeaf.new('col', Operators::BLANK)
            allow(@child_collection_book).to receive(:list).and_return([])
            decorated_book.list(
              caller,
              Filter.new(condition_tree: tree),
              Projection.new(['col'])
            )

            expect(@child_collection_book).to have_received(:list) do |context_caller, filter, projection|
              expect(context_caller).to eq caller
              expect(filter.condition_tree.to_h).to include(field: 'col', operator: Operators::EQUAL, value: nil)
              expect(projection).to eq Projection.new(['col'])
            end
          end
        end
      end
    end
  end
end
