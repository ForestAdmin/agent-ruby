require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module LazyJoin
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Decorators
      include ForestAdminDatasourceToolkit::Schema

      describe LazyJoinCollectionDecorator do
        subject(:lazy_join_collection_decorator) { described_class }

        let(:caller) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }
        let(:aggregation) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Aggregation) }

        before do
          datasource = Datasource.new
          @collection_book = build_collection(
            name: 'book',
            schema: {
              fields: {
                'id' => build_numeric_primary_key,
                'author_id' => build_column(column_type: 'Number'),
                'editor_id' => build_column(column_type: 'Number'),
                'author' => build_many_to_one(foreign_collection: 'person', foreign_key: 'author_id'),
                'editor' => build_many_to_one(foreign_collection: 'person', foreign_key: 'editor_id'),
                'title' => build_column,
                'price' => build_column(column_type: 'Number')
              }
            }
          )

          @collection_person = build_collection(
            name: 'person',
            schema: {
              fields: {
                'id' => build_numeric_primary_key,
                'books' => build_one_to_many(foreign_collection: 'person', origin_key: 'author_id'),
                'first_name' => build_column,
                'last_name' => build_column
              }
            }
          )
          datasource.add_collection(@collection_book)
          datasource.add_collection(@collection_person)

          @datasource_decorator = DatasourceDecorator.new(datasource, lazy_join_collection_decorator)
        end

        context 'when call list' do
          it 'not join when projection ask for target field only' do
            allow(@collection_book).to receive(:list).and_return(
              [{ 'id' => 1, 'author_id' => 2 }, { 'id' => 2, 'author_id' => 5 }]
            )

            result = @datasource_decorator.get_collection('book')
                                          .list(caller, Filter.new, Projection.new(%w[id author:id]))

            expect(@collection_book).to have_received(:list) do |_caller, _filter, projection|
              expect(projection).to eq(%w[id author_id])
            end
            expect(result).to eq([{ 'id' => 1, 'author' => { 'id' => 2 } }, { 'id' => 2, 'author' => { 'id' => 5 } }])
          end

          it 'not join when projection ask for target field only with multiple relations' do
            allow(@collection_book).to receive(:list).and_return(
              [
                { 'id' => 1, 'author_id' => 2, 'editor_id' => 3 },
                { 'id' => 2, 'author_id' => 5, 'editor_id' => 4 }
              ]
            )

            result = @datasource_decorator.get_collection('book')
                                          .list(caller, Filter.new, Projection.new(%w[id author:id editor:id]))

            expect(@collection_book).to have_received(:list) do |_caller, _filter, projection|
              expect(projection).to eq(%w[id author_id editor_id])
            end
            expect(result).to eq(
              [
                { 'id' => 1, 'author' => { 'id' => 2 }, 'editor' => { 'id' => 3 } },
                { 'id' => 2, 'author' => { 'id' => 5 }, 'editor' => { 'id' => 4 } }
              ]
            )
          end

          it 'join when projection ask for multiple fields in foreign collection' do
            allow(@collection_book).to receive(:list).and_return(
              [
                { 'id' => 1, 'author' => { 'id' => 2, 'first_name' => 'Isaac' } },
                { 'id' => 2, 'author' => { 'id' => 5, 'first_name' => 'J.K' } }
              ]
            )

            result = @datasource_decorator.get_collection('book')
                                          .list(caller, Filter.new, Projection.new(%w[id author:id author:first_name]))

            expect(@collection_book).to have_received(:list) do |_caller, _filter, projection|
              expect(projection).to eq(%w[id author:id author:first_name])
            end
            expect(result).to eq(
              [
                { 'id' => 1, 'author' => { 'id' => 2, 'first_name' => 'Isaac' } },
                { 'id' => 2, 'author' => { 'id' => 5, 'first_name' => 'J.K' } }
              ]
            )
          end

          it 'not join when when condition tree is on foreign key target' do
            allow(@collection_book).to receive(:list).and_return(
              [{ 'id' => 1, 'author_id' => 2 }, { 'id' => 2, 'author_id' => 5 }, { 'id' => 3, 'author_id' => 5 }]
            )

            @datasource_decorator.get_collection('book').list(
              caller,
              Filter.new(condition_tree: Nodes::ConditionTreeLeaf.new('author:id', Operators::IN, [2, 5])),
              Projection.new(%w[id author:id])
            )

            expect(@collection_book).to have_received(:list) do |_caller, filter, projection|
              condition_tree = Nodes::ConditionTreeLeaf.new('author_id', Operators::IN, [2, 5]).to_h
              expect(filter.condition_tree.to_h).to eq(condition_tree)
              expect(projection).to eq(%w[id author_id])
            end
          end

          it 'join when when condition tree is on foreign key collection_field' do
            allow(@collection_book).to receive(:list).and_return(
              [
                { 'id' => 1, 'author' => { 'id' => 2, 'first_name' => 'Isaac' } },
                { 'id' => 2, 'author' => { 'id' => 5, 'first_name' => 'J.K' } },
                { 'id' => 3, 'author' => { 'id' => 5, 'first_name' => 'J.K' } }
              ]
            )

            condition_tree = Nodes::ConditionTreeLeaf.new('author:first_name', Operators::EQUAL, 'J.K')
            @datasource_decorator.get_collection('book').list(
              caller,
              Filter.new(condition_tree: condition_tree),
              Projection.new(%w[id author:id])
            )

            expect(@collection_book).to have_received(:list) do |_caller, filter, projection|
              expect(filter.condition_tree).to eq(condition_tree)
              expect(projection).to eq(%w[id author_id])
            end
          end

          it 'disable join on condition tree but not in projection' do
            allow(@collection_book).to receive(:list).and_return(
              [
                { 'id' => 1, 'author' => { 'first_name' => 'Isaac' } },
                { 'id' => 2, 'author' => { 'first_name' => 'J.K' } },
                { 'id' => 3, 'author' => { 'first_name' => 'J.K' } }
              ]
            )

            condition_tree = Nodes::ConditionTreeLeaf.new('author:id', Operators::IN, [2, 5])
            result = @datasource_decorator.get_collection('book').list(
              caller,
              Filter.new(condition_tree: condition_tree),
              Projection.new(%w[id author:first_name])
            )

            expect(@collection_book).to have_received(:list) do |_caller, filter, projection|
              condition_tree = Nodes::ConditionTreeLeaf.new('author_id', Operators::IN, [2, 5])
              expect(filter.condition_tree.to_h).to eq(condition_tree.to_h)
              expect(projection).to eq(%w[id author:first_name])
            end
            expect(result).to eq(
              [
                { 'id' => 1, 'author' => { 'first_name' => 'Isaac' } },
                { 'id' => 2, 'author' => { 'first_name' => 'J.K' } },
                { 'id' => 3, 'author' => { 'first_name' => 'J.K' } }
              ]
            )
          end

          it 'disable join on projection but not on condition tree' do
            allow(@collection_book).to receive(:list).and_return(
              [
                { 'id' => 1, 'author_id' => 2 },
                { 'id' => 2, 'author_id' => 5 },
                { 'id' => 3, 'author_id' => 5 }
              ]
            )

            condition_tree = Nodes::ConditionTreeLeaf.new('author:first_name', Operators::IN, %w[Isaac J.K])
            result = @datasource_decorator.get_collection('book').list(
              caller,
              Filter.new(condition_tree: condition_tree),
              Projection.new(%w[id author:id])
            )

            expect(@collection_book).to have_received(:list) do |_caller, filter, projection|
              expect(filter.condition_tree.to_h).to eq(condition_tree.to_h)
              expect(projection).to eq(%w[id author_id])
            end
            expect(result).to eq(
              [
                { 'id' => 1, 'author' => { 'id' => 2 } },
                { 'id' => 2, 'author' => { 'id' => 5 } },
                { 'id' => 3, 'author' => { 'id' => 5 } }
              ]
            )
          end

          it 'correctly handle null relations' do
            allow(@collection_book).to receive(:list).and_return(
              [{ 'id' => 1, 'author_id' => 2 }, { 'id' => 2, 'author_id' => nil }]
            )

            result = @datasource_decorator.get_collection('book').list(caller, Filter.new, Projection.new(%w[id author:id]))

            expect(@collection_book).to have_received(:list) do |_caller, _filter, projection|
              expect(projection).to eq(%w[id author_id])
            end
            expect(result).to eq([{ 'id' => 1, 'author' => { 'id' => 2 } }, { 'id' => 2, 'author' => nil }])
          end
        end

        context 'when call aggregate' do
          it 'not join on aggregate when group by foreign key' do
            allow(@collection_book).to receive(:aggregate).and_return(
              [
                { 'value' => 1824.11, 'group' => { 'author_id' => 2 } },
                { 'value' => 824.11, 'group' => { 'author_id' => 3 } }
              ]
            )

            result = @datasource_decorator.get_collection('book').aggregate(
              caller,
              Filter.new,
              Aggregation.new(operation: 'Sum', field: 'price', groups: [{ field: 'author:id' }])
            )

            expect(@collection_book).to have_received(:aggregate) do |_caller, _filter, aggregation|
              expect(aggregation.to_h).to eq(
                Aggregation.new(operation: 'Sum', field: 'price', groups: [{ field: 'author_id', operation: nil }]).to_h
              )
            end
            expect(result).to eq(
              [
                { 'value' => 1824.11, 'group' => { 'author:id' => 2 } },
                { 'value' => 824.11, 'group' => { 'author:id' => 3 } }
              ]
            )
          end

          it 'join on aggregate when group by foreign field' do
            allow(@collection_book).to receive(:aggregate).and_return(
              [
                { 'value' => 1824.11, 'group' => { 'author:first_name' => 'Isaac' } },
                { 'value' => 824.11, 'group' => { 'author:first_name' => 'JK' } }
              ]
            )

            result = @datasource_decorator.get_collection('book').aggregate(
              caller,
              Filter.new,
              Aggregation.new(operation: 'Sum', field: 'price', groups: [{ field: 'author:first_name' }])
            )

            expect(@collection_book).to have_received(:aggregate) do |_caller, _filter, aggregation|
              expect(aggregation.to_h).to eq(
                Aggregation.new(
                  operation: 'Sum',
                  field: 'price',
                  groups: [{ field: 'author:first_name', operation: nil }]
                ).to_h
              )
            end
            expect(result).to eq(
              [
                { 'value' => 1824.11, 'group' => { 'author:first_name' => 'Isaac' } },
                { 'value' => 824.11, 'group' => { 'author:first_name' => 'JK' } }
              ]
            )
          end

          it 'not join on aggregate when group by foreign pk and filter on foreign pk' do
            allow(@collection_book).to receive(:aggregate).and_return(
              [
                { 'value' => 1824.11, 'group' => { 'author_id' => 2 } },
                { 'value' => 824.11, 'group' => { 'author_id' => 3 } }
              ]
            )

            result = @datasource_decorator.get_collection('book').aggregate(
              caller,
              Filter.new(condition_tree: Nodes::ConditionTreeLeaf.new('author:id', Operators::NOT_EQUAL, 50)),
              Aggregation.new(operation: 'Sum', field: 'price', groups: [{ field: 'author:id' }])
            )

            expect(@collection_book).to have_received(:aggregate) do |_caller, filter, aggregation|
              expect(filter.condition_tree.to_h).to eq(
                Nodes::ConditionTreeLeaf.new('author_id', Operators::NOT_EQUAL, 50).to_h
              )
              expect(aggregation.to_h).to eq(
                Aggregation.new(
                  operation: 'Sum',
                  field: 'price',
                  groups: [{ field: 'author_id', operation: nil }]
                ).to_h
              )
            end
            expect(result).to eq(
              [
                { 'value' => 1824.11, 'group' => { 'author:id' => 2 } },
                { 'value' => 824.11, 'group' => { 'author:id' => 3 } }
              ]
            )
          end

          it 'join on aggregate when group by foreign pk and filter on foreign field' do
            allow(@collection_book).to receive(:aggregate).and_return(
              [
                { 'value' => 1824.11, 'group' => { 'author_id' => 2 } },
                { 'value' => 824.11, 'group' => { 'author_id' => 3 } }
              ]
            )

            result = @datasource_decorator.get_collection('book').aggregate(
              caller,
              Filter.new(
                condition_tree: Nodes::ConditionTreeLeaf.new(
                  'author:first_name',
                  Operators::NOT_EQUAL,
                  'wrong_name'
                )
              ),
              Aggregation.new(operation: 'Sum', field: 'price', groups: [{ field: 'author:id' }])
            )

            expect(@collection_book).to have_received(:aggregate) do |_caller, filter, aggregation|
              expect(filter.condition_tree.to_h).to eq(
                Nodes::ConditionTreeLeaf.new('author:first_name', Operators::NOT_EQUAL, 'wrong_name').to_h
              )
              expect(aggregation.to_h).to eq(
                Aggregation.new(
                  operation: 'Sum',
                  field: 'price',
                  groups: [{ field: 'author_id', operation: nil }]
                ).to_h
              )
            end
            expect(result).to eq(
              [
                { 'value' => 1824.11, 'group' => { 'author:id' => 2 } },
                { 'value' => 824.11, 'group' => { 'author:id' => 3 } }
              ]
            )
          end
        end
      end
    end
  end
end
