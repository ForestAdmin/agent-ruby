require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Query
      module ConditionTree
        include Nodes
        include ForestAdminDatasourceToolkit::Exceptions
        include ForestAdminDatasourceToolkit::Schema
        include ForestAdminDatasourceToolkit::Utils

        describe ConditionTreeFactory do
          subject(:condition_tree_factory) { described_class }

          let(:datasource) { Datasource.new }

          context 'when testing match_records / match_ids' do
            it 'raises an error when the collection has no primary key' do
              collection = Collection.new(datasource, 'cars')
              collection.add_fields({ 'column' => ColumnSchema.new(column_type: PrimitiveType::STRING) })

              expect do
                condition_tree_factory.match_ids(collection, [[]])
              end.to raise_error(ForestException, 'Collection must have at least one primary key')
            end

            it 'raises an error when the collection does not support equal and in' do
              collection = Collection.new(datasource, 'cars')
              collection.add_fields({ 'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true) })

              expect do
                condition_tree_factory.match_ids(collection, [[]])
              end.to raise_error(ForestException, "Field 'id' must support operators: ['Equal', 'In']")
            end

            it 'generates matchNone with simple PK' do
              collection = Collection.new(datasource, 'cars')
              collection.add_fields({ 'id' => ColumnSchema.new(
                column_type: PrimitiveType::NUMBER,
                filter_operators: [Operators::EQUAL, Operators::IN],
                is_primary_key: true
              ) })

              expect(condition_tree_factory.match_records(collection, [])).to have_attributes(aggregator: 'Or', conditions: [])
            end

            it 'generates equal with simple PK' do
              collection = Collection.new(datasource, 'cars')
              collection.add_fields({ 'id' => ColumnSchema.new(
                column_type: PrimitiveType::NUMBER,
                filter_operators: [Operators::EQUAL, Operators::IN],
                is_primary_key: true
              ) })

              expect(condition_tree_factory.match_records(collection, [{ 'id' => 1 }])).to have_attributes(field: 'id', operator: Operators::EQUAL, value: 1)
            end

            it 'generates "In" with simple PK' do
              collection = Collection.new(datasource, 'cars')
              collection.add_fields({ 'id' => ColumnSchema.new(
                column_type: PrimitiveType::NUMBER,
                filter_operators: [Operators::EQUAL, Operators::IN],
                is_primary_key: true
              ) })

              expect(condition_tree_factory.match_records(collection, [{ 'id' => 1 }, { 'id' => 2 }])).to have_attributes(field: 'id', operator: Operators::IN, value: [1, 2])
            end

            it 'generates a simple "And" with a composite PK' do
              collection = Collection.new(datasource, 'cars')
              collection.add_fields(
                {
                  'col1' => ColumnSchema.new(
                    column_type: PrimitiveType::NUMBER,
                    filter_operators: [Operators::EQUAL, Operators::IN],
                    is_primary_key: true
                  ),
                  'col2' => ColumnSchema.new(
                    column_type: PrimitiveType::NUMBER,
                    filter_operators: [Operators::EQUAL, Operators::IN],
                    is_primary_key: true
                  )
                }
              )

              expect(condition_tree_factory.match_records(collection, [{ 'col1' => 1, 'col2' => 1 }]))
                .to have_attributes(
                  aggregator: 'And',
                  conditions: contain_exactly(
                    have_attributes(field: 'col1', operator: Operators::EQUAL, value: 1),
                    have_attributes(field: 'col2', operator: Operators::EQUAL, value: 1)
                  )
                )
            end

            it 'factorizes with a composite PK' do
              collection = Collection.new(datasource, 'cars')
              collection.add_fields(
                {
                  'col1' => ColumnSchema.new(
                    column_type: PrimitiveType::NUMBER,
                    filter_operators: [Operators::EQUAL, Operators::IN],
                    is_primary_key: true
                  ),
                  'col2' => ColumnSchema.new(
                    column_type: PrimitiveType::NUMBER,
                    filter_operators: [Operators::EQUAL, Operators::IN],
                    is_primary_key: true
                  )
                }
              )

              expect(condition_tree_factory.match_records(collection, [{ 'col1' => 1, 'col2' => 1 }, { 'col1' => 1, 'col2' => 2 }]))
                .to have_attributes(
                  aggregator: 'And',
                  conditions: contain_exactly(
                    have_attributes(field: 'col1', operator: Operators::EQUAL, value: 1),
                    have_attributes(field: 'col2', operator: Operators::IN, value: [1, 2])
                  )
                )
            end

            it 'does not factorize with a composite PK' do
              collection = Collection.new(datasource, 'cars')
              collection.add_fields(
                {
                  'col1' => ColumnSchema.new(
                    column_type: PrimitiveType::NUMBER,
                    filter_operators: [Operators::EQUAL, Operators::IN],
                    is_primary_key: true
                  ),
                  'col2' => ColumnSchema.new(
                    column_type: PrimitiveType::NUMBER,
                    filter_operators: [Operators::EQUAL, Operators::IN],
                    is_primary_key: true
                  )
                }
              )

              expect(condition_tree_factory.match_records(collection, [{ 'col1' => 1, 'col2' => 1 }, { 'col1' => 2, 'col2' => 2 }]))
                .to have_attributes(
                  aggregator: 'Or',
                  conditions: contain_exactly(
                    have_attributes(
                      aggregator: 'And',
                      conditions: contain_exactly(
                        have_attributes(field: 'col1', operator: Operators::EQUAL, value: 1),
                        have_attributes(field: 'col2', operator: Operators::EQUAL, value: 1)
                      )
                    ),
                    have_attributes(
                      aggregator: 'And',
                      conditions: contain_exactly(
                        have_attributes(field: 'col1', operator: Operators::EQUAL, value: 2),
                        have_attributes(field: 'col2', operator: Operators::EQUAL, value: 2)
                      )
                    )
                  )
                )
            end

            it 'supports hash format with simple PK (when called via match_ids)' do
              collection = Collection.new(datasource, 'cars')
              collection.add_fields({ 'id' => ColumnSchema.new(
                column_type: PrimitiveType::NUMBER,
                filter_operators: [Operators::EQUAL, Operators::IN],
                is_primary_key: true
              ) })

              # Test with hash format (as returned by unpack_id with with_key: true)
              expect(condition_tree_factory.match_ids(collection, [{ 'id' => 1 }]))
                .to have_attributes(field: 'id', operator: Operators::EQUAL, value: 1)
            end

            it 'supports hash format with composite PK (when called via match_ids)' do
              collection = Collection.new(datasource, 'cars')
              collection.add_fields(
                {
                  'col1' => ColumnSchema.new(
                    column_type: PrimitiveType::NUMBER,
                    filter_operators: [Operators::EQUAL, Operators::IN],
                    is_primary_key: true
                  ),
                  'col2' => ColumnSchema.new(
                    column_type: PrimitiveType::NUMBER,
                    filter_operators: [Operators::EQUAL, Operators::IN],
                    is_primary_key: true
                  )
                }
              )

              # Test with hash format (as returned by unpack_id with with_key: true)
              expect(condition_tree_factory.match_ids(collection, [{ 'col1' => 1, 'col2' => 2 }]))
                .to have_attributes(
                  aggregator: 'And',
                  conditions: contain_exactly(
                    have_attributes(field: 'col1', operator: Operators::EQUAL, value: 1),
                    have_attributes(field: 'col2', operator: Operators::EQUAL, value: 2)
                  )
                )
            end

            it 'supports hash format with multiple composite PKs' do
              collection = Collection.new(datasource, 'cars')
              collection.add_fields(
                {
                  'col1' => ColumnSchema.new(
                    column_type: PrimitiveType::NUMBER,
                    filter_operators: [Operators::EQUAL, Operators::IN],
                    is_primary_key: true
                  ),
                  'col2' => ColumnSchema.new(
                    column_type: PrimitiveType::NUMBER,
                    filter_operators: [Operators::EQUAL, Operators::IN],
                    is_primary_key: true
                  )
                }
              )

              # Test with hash format - multiple records with same col1 (factorization)
              expect(condition_tree_factory.match_ids(collection, [{ 'col1' => 1, 'col2' => 1 }, { 'col1' => 1, 'col2' => 2 }]))
                .to have_attributes(
                  aggregator: 'And',
                  conditions: contain_exactly(
                    have_attributes(field: 'col1', operator: Operators::EQUAL, value: 1),
                    have_attributes(field: 'col2', operator: Operators::IN, value: [1, 2])
                  )
                )
            end
          end

          context 'when testing intersect' do
            it 'returns null when called with an empty list' do
              tree = condition_tree_factory.intersect

              expect(tree).to be_nil
            end

            it 'returns the parameter when called with only one param' do
              tree = condition_tree_factory.intersect([ConditionTreeLeaf.new('column', Operators::EQUAL, true)])

              expect(tree).to have_attributes(field: 'column', operator: Operators::EQUAL, value: true)
            end

            it 'ignores null params' do
              tree = condition_tree_factory.intersect([nil, ConditionTreeLeaf.new('column', Operators::EQUAL, true), nil])

              expect(tree).to have_attributes(field: 'column', operator: Operators::EQUAL, value: true)
            end

            it 'returns multiple trees when receiving multiple trees' do
              condition_tree = ConditionTreeLeaf.new('column', Operators::EQUAL, true)
              other_condition_tree = ConditionTreeLeaf.new('otherColumn', Operators::EQUAL, true)
              tree = condition_tree_factory.intersect([condition_tree, other_condition_tree])

              expect(tree).to have_attributes(
                aggregator: 'And',
                conditions: contain_exactly(
                  have_attributes(field: 'column', operator: Operators::EQUAL, value: true),
                  have_attributes(field: 'otherColumn', operator: Operators::EQUAL, value: true)
                )
              )
            end
          end

          context 'when testing from_plain_object' do
            it 'raises an error when calling with badly formatted json' do
              expect do
                condition_tree_factory.from_plain_object('this is not json')
              end.to raise_error('Failed to instantiate condition tree from json')
            end

            it 'works with a simple case' do
              tree = condition_tree_factory.from_plain_object(
                { field: 'field', operator: Operators::EQUAL, value: 'something' }
              )

              expect(tree).to have_attributes(field: 'field', operator: Operators::EQUAL, value: 'something')
            end

            it 'removes useless aggregators from the frontend' do
              tree = condition_tree_factory.from_plain_object(
                { aggregator: 'And', conditions: [{ field: 'field', operator: Operators::EQUAL, value: 'something' }] }
              )

              expect(tree).to have_attributes(field: 'field', operator: Operators::EQUAL, value: 'something')
            end

            it 'works with an aggregator' do
              tree = condition_tree_factory.from_plain_object(
                {
                  aggregator: 'And',
                  conditions: [
                    { field: 'field', operator: Operators::EQUAL, value: 'something' },
                    { field: 'field', operator: Operators::EQUAL, value: 'something' }
                  ]
                }
              )

              expect(tree).to have_attributes(
                aggregator: 'And',
                conditions: contain_exactly(
                  have_attributes(field: 'field', operator: Operators::EQUAL, value: 'something'),
                  have_attributes(field: 'field', operator: Operators::EQUAL, value: 'something')
                )
              )
            end
          end
        end
      end
    end
  end
end
