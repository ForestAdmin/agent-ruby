require 'spec_helper'

module ForestAdminAgent
  module Utils
    include ForestAdminDatasourceToolkit
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Exceptions
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes

    describe ConditionTreeParser do
      subject(:condition_tree_parser) { described_class }

      let(:collection_category) do
        datasource = Datasource.new
        collection_category = Collection.new(datasource, 'Category')
        collection_category.add_fields(
          {
            'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                     filter_operators: [Operators::GREATER_THAN, Operators::LESS_THAN]),
            'label' => ColumnSchema.new(column_type: 'String'),
            'active' => ColumnSchema.new(column_type: PrimitiveType::BOOLEAN, filter_operators: [Operators::IN])
          }
        )

        datasource.add_collection(collection_category)

        return collection_category
      end

      it 'faileds if provided something else' do
        expect do
          condition_tree_parser.from_plain_object(collection_category,
                                                  {})
        end.to raise_error(ForestException, '🌳🌳🌳 Failed to instantiate condition tree')
      end

      it 'works with aggregator' do
        filters = {
          'aggregator' => 'And',
          'conditions' => [
            { 'field' => 'id', 'operator' => 'Less_Than', 'value' => 'something' },
            { 'field' => 'id', 'operator' => 'Greater_Than', 'value' => 'something' }
          ]
        }

        expect(condition_tree_parser.from_plain_object(collection_category, filters))
          .eql?(ConditionTreeBranch.new(
                  filters['aggregator'].capitalize,
                  [
                    ConditionTreeLeaf.new(
                      filters['conditions'][0]['field'],
                      filters['conditions'][0]['operator'],
                      filters['conditions'][0]['value']
                    ),
                    ConditionTreeLeaf.new(
                      filters['conditions'][1]['field'],
                      filters['conditions'][1]['operator'],
                      filters['conditions'][1]['value']
                    )
                  ]
                ))
      end

      it 'works with single condition without aggregator' do
        filters = { 'field' => 'id', 'operator' => 'Less_Than', 'value' => 'something' }

        expect(condition_tree_parser.from_plain_object(collection_category, filters))
          .eql?(ConditionTreeLeaf.new(filters['field'], filters['operator'], filters['value']))
      end

      it 'works with "IN" on a string' do
        filters = { 'field' => 'label', 'operator' => 'In', 'value' => ' id1,id2 , id3' }

        expect(condition_tree_parser.from_plain_object(collection_category,  filters))
          .eql?(ConditionTreeLeaf.new(filters['field'], filters['operator'], filters['value']))
      end

      it 'works with "IN" on a boolean' do
        filters = { 'field' => 'active', 'operator' => 'In', 'value' => 'true,0,false,yes,no' }

        expect(condition_tree_parser.from_plain_object(collection_category, filters))
          .eql?(ConditionTreeLeaf.new(filters['field'], filters['operator'], filters['value']))
      end

      it 'works with "IN" on a number' do
        filters = { 'field' => 'id', 'operator' => 'In', 'value' => '1,2,3' }

        expect(condition_tree_parser.from_plain_object(collection_category, filters))
          .eql?(ConditionTreeLeaf.new(filters['field'], filters['operator'], filters['value']))
      end
    end
  end
end
