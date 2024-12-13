require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Empty
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Decorators
      include ForestAdminDatasourceToolkit::Schema

      describe EmptyCollectionDecorator do
        subject(:empty_collection_decorator) { described_class }

        let(:caller) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }
        let(:category) { @datasource_decorator.get_collection('category') }
        let(:aggregation) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Aggregation) }

        before do
          datasource = Datasource.new
          @collection_category = build_collection(
            name: 'category',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                         filter_operators: [Operators::EQUAL, Operators::IN]),
                'label' => ColumnSchema.new(column_type: 'String')
              }
            }
          )
          datasource.add_collection(@collection_category)

          @datasource_decorator = DatasourceDecorator.new(datasource, empty_collection_decorator)
        end

        it 'schema should not be changed' do
          expect(@datasource_decorator.get_collection('category').schema).to eq(@collection_category.schema)
        end

        context 'with valid query on crud' do
          it 'list() should be called with overlapping Ins' do
            allow(category).to receive(:list).and_return([{ id: 2 }])

            records = category.list(
              caller,
              Filter.new(
                condition_tree: Nodes::ConditionTreeBranch.new(
                  'And',
                  [
                    Nodes::ConditionTreeLeaf.new('id', 'In', [1, 2]),
                    Nodes::ConditionTreeLeaf.new('id', 'In', [2, 3])
                  ]
                )
              ),
              Projection.new
            )

            expect(records).to eq([{ id: 2 }])
            expect(category).to have_received(:list)
          end

          it 'list() should be called with empty And' do
            allow(category).to receive(:list).and_return([{ id: 2 }])
            records = category.list(
              caller,
              Filter.new(condition_tree: Nodes::ConditionTreeBranch.new('And', [])),
              Projection.new
            )

            expect(records).to eq([{ id: 2 }])
            expect(category).to have_received(:list)
          end

          it 'list() should be called with only non Equal/In leafs' do
            allow(category).to receive(:list).and_return([{ id: 2 }])
            records = category.list(
              caller,
              Filter.new(
                condition_tree: Nodes::ConditionTreeBranch.new(
                  'And',
                  [
                    Nodes::ConditionTreeLeaf.new('id', 'Today', nil)
                  ]
                )
              ),
              Projection.new
            )

            expect(records).to eq([{ id: 2 }])
            expect(category).to have_received(:list)
          end

          it 'update() should be called with overlapping incompatible equals' do
            allow(category).to receive(:update).and_return(nil)

            category.update(
              caller,
              Filter.new(
                condition_tree: Nodes::ConditionTreeBranch.new(
                  'Or',
                  [
                    Nodes::ConditionTreeLeaf.new('id', 'Equal', 4),
                    Nodes::ConditionTreeLeaf.new('id', 'Equal', 5)
                  ]
                )
              ),
              { label: 'new label' }
            )

            expect(category).to have_received(:update)
          end

          it 'delete() should be called with null condition Tree' do
            allow(category).to receive(:delete).and_return(nil)
            category.delete(caller, Filter.new(condition_tree: nil))

            expect(category).to have_received(:delete)
          end

          it 'aggregate() should be called with simple query' do
            allow(category).to receive(:aggregate).and_return([{ value: 2, group: {} }])
            records = category.aggregate(
              caller,
              Filter.new(condition_tree: Nodes::ConditionTreeLeaf.new('id', 'Equal', nil)),
              aggregation
            )

            expect(records).to eq([{ value: 2, group: {} }])
            expect(category).to have_received(:aggregate)
          end
        end

        context 'with queries which target an impossible filter' do
          it 'list() should not be called with empty In' do
            allow(@collection_category).to receive(:list).and_return([])
            records = category.list(
              caller,
              Filter.new(condition_tree: Nodes::ConditionTreeLeaf.new('id', 'In', [])),
              Projection.new
            )

            expect(records).to eq([])
            expect(@collection_category).not_to have_received(:list)
          end

          it 'list() should not be called with nested empty In' do
            allow(@collection_category).to receive(:list).and_return([])
            records = category.list(
              caller,
              Filter.new(
                condition_tree: Nodes::ConditionTreeBranch.new(
                  'And',
                  [
                    Nodes::ConditionTreeBranch.new(
                      'And',
                      [
                        Nodes::ConditionTreeBranch.new(
                          'Or',
                          [
                            Nodes::ConditionTreeLeaf.new('id', 'In', [])
                          ]
                        )
                      ]
                    )
                  ]
                )
              ),
              Projection.new
            )

            expect(records).to eq([])
            expect(@collection_category).not_to have_received(:list)
          end

          it 'delete() should not be called with incompatible Equals' do
            allow(@collection_category).to receive(:delete).and_return(nil)
            category.delete(
              caller,
              Filter.new(
                condition_tree: Nodes::ConditionTreeBranch.new(
                  'And',
                  [
                    Nodes::ConditionTreeLeaf.new('id', 'Equal', 12),
                    Nodes::ConditionTreeLeaf.new('id', 'Equal', 13)
                  ]
                )
              )
            )

            expect(@collection_category).not_to have_received(:delete)
          end

          it 'update() should not be called with incompatible Equal/In' do
            allow(@collection_category).to receive(:update).and_return(nil)
            category.update(
              caller,
              Filter.new(
                condition_tree: Nodes::ConditionTreeBranch.new(
                  'And',
                  [
                    Nodes::ConditionTreeLeaf.new('id', 'Equal', 12),
                    Nodes::ConditionTreeLeaf.new('id', 'In', [13])
                  ]
                )
              ),
              { label: 'new label' }
            )

            expect(@collection_category).not_to have_received(:update)
          end

          it 'aggregate() should not be called with incompatible Ins' do
            allow(@collection_category).to receive(:aggregate).and_return([])
            records = category.aggregate(
              caller,
              Filter.new(
                condition_tree: Nodes::ConditionTreeBranch.new(
                  'And',
                  [
                    Nodes::ConditionTreeLeaf.new('id', 'In', [34, 32]),
                    Nodes::ConditionTreeLeaf.new('id', 'In', [13])
                  ]
                )
              ),
              aggregation
            )

            expect(records).to eq([])
            expect(@collection_category).not_to have_received(:aggregate)
          end
        end
      end
    end
  end
end
