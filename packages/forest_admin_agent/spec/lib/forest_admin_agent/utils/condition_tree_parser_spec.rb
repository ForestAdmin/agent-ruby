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
                                     filter_operators: [Operators::GREATER_THAN, Operators::LESS_THAN, Operators::IN, Operators::NOT_IN]),
            'label' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::IN, Operators::NOT_IN, Operators::INCLUDES_ALL]),
            'active' => ColumnSchema.new(column_type: PrimitiveType::BOOLEAN, filter_operators: [Operators::IN, Operators::NOT_IN])
          }
        )

        datasource.add_collection(collection_category)

        return collection_category
      end

      it 'failed if provided something else' do
        expect do
          condition_tree_parser.from_plain_object(collection_category,
                                                  {})
        end.to raise_error(ForestException, /Failed to instantiate condition tree/)
      end

      it 'works with aggregator' do
        filters = {
          aggregator: 'And',
          conditions: [
            { field: 'id', operator: Operators::LESS_THAN, value: 10 },
            { field: 'id', operator: Operators::GREATER_THAN, value: 5 }
          ]
        }
        result = condition_tree_parser.from_plain_object(collection_category, filters)
        expect(result)
          .to have_attributes(
            aggregator: filters[:aggregator].capitalize,
            conditions: contain_exactly(have_attributes(
                                          field: filters[:conditions][0][:field],
                                          operator: filters[:conditions][0][:operator],
                                          value: filters[:conditions][0][:value].to_f
                                        ), have_attributes(
                                             field: filters[:conditions][1][:field],
                                             operator: filters[:conditions][1][:operator],
                                             value: filters[:conditions][1][:value].to_f
                                           ))
          )
      end

      it 'works with single condition without aggregator' do
        filters = { field: 'id', operator: Operators::LESS_THAN, value: 42 }

        expect(condition_tree_parser.from_plain_object(collection_category, filters))
          .to have_attributes(field: filters[:field], operator: filters[:operator], value: filters[:value].to_f)
      end

      it 'works with "IN" on a string' do
        filters = { field: 'label', operator: Operators::IN, value: ' id1,id2 , id3' }

        expect(condition_tree_parser.from_plain_object(collection_category, filters))
          .to have_attributes(field: filters[:field], operator: filters[:operator], value: %w[id1 id2 id3])
      end

      it 'works with "IN" on a boolean' do
        filters = { field: 'active', operator: Operators::IN, value: 'true,0,false,yes,no' }

        expect(condition_tree_parser.from_plain_object(collection_category, filters))
          .to have_attributes(field: filters[:field], operator: filters[:operator], value: [true, false, false, true, false])
      end

      it 'works with "IN" on a number' do
        filters = { field: 'id', operator: Operators::IN, value: '1,2,3' }

        expect(condition_tree_parser.from_plain_object(collection_category, filters))
          .to have_attributes(field: filters[:field], operator: filters[:operator], value: [1, 2, 3])
      end

      it 'works with "IN" on a string when value is already an array' do
        filters = { field: 'label', operator: Operators::IN, value: %w[id1 id2 id3] }

        expect(condition_tree_parser.from_plain_object(collection_category, filters))
          .to have_attributes(field: filters[:field], operator: filters[:operator], value: %w[id1 id2 id3])
      end

      it 'works with "IN" on a number when value is already an array of strings' do
        filters = { field: 'id', operator: Operators::IN, value: %w[27 28 29] }

        expect(condition_tree_parser.from_plain_object(collection_category, filters))
          .to have_attributes(field: filters[:field], operator: filters[:operator], value: [27.0, 28.0, 29.0])
      end

      it 'works with "IN" on a number when value is already an array of numbers' do
        filters = { field: 'id', operator: Operators::IN, value: [27, 28, 29] }

        expect(condition_tree_parser.from_plain_object(collection_category, filters))
          .to have_attributes(field: filters[:field], operator: filters[:operator], value: [27, 28, 29])
      end

      it 'works with "IN" on a boolean when value is already an array' do
        filters = { field: 'active', operator: Operators::IN, value: %w[true 0 false yes no] }

        expect(condition_tree_parser.from_plain_object(collection_category, filters))
          .to have_attributes(field: filters[:field], operator: filters[:operator], value: [true, false, false, true, false])
      end

      context 'with NOT_IN operator' do
        it 'works with "NOT_IN" on a string (comma-separated)' do
          filters = { field: 'label', operator: Operators::NOT_IN, value: 'id1,id2,id3' }

          expect(condition_tree_parser.from_plain_object(collection_category, filters))
            .to have_attributes(field: filters[:field], operator: filters[:operator], value: %w[id1 id2 id3])
        end

        it 'works with "NOT_IN" on a string when value is already an array' do
          filters = { field: 'label', operator: Operators::NOT_IN, value: %w[id1 id2 id3] }

          expect(condition_tree_parser.from_plain_object(collection_category, filters))
            .to have_attributes(field: filters[:field], operator: filters[:operator], value: %w[id1 id2 id3])
        end

        it 'works with "NOT_IN" on a number when value is already an array of strings' do
          filters = { field: 'id', operator: Operators::NOT_IN, value: %w[27 28 29] }

          expect(condition_tree_parser.from_plain_object(collection_category, filters))
            .to have_attributes(field: filters[:field], operator: filters[:operator], value: [27.0, 28.0, 29.0])
        end

        it 'works with "NOT_IN" on a boolean when value is already an array' do
          filters = { field: 'active', operator: Operators::NOT_IN, value: ['true', 'false'] }

          expect(condition_tree_parser.from_plain_object(collection_category, filters))
            .to have_attributes(field: filters[:field], operator: filters[:operator], value: [true, false])
        end
      end

      context 'with INCLUDES_ALL operator' do
        it 'works with "INCLUDES_ALL" on a string (comma-separated)' do
          filters = { field: 'label', operator: Operators::INCLUDES_ALL, value: 'tag1,tag2,tag3' }

          expect(condition_tree_parser.from_plain_object(collection_category, filters))
            .to have_attributes(field: filters[:field], operator: filters[:operator], value: %w[tag1 tag2 tag3])
        end

        it 'works with "INCLUDES_ALL" on a string when value is already an array' do
          filters = { field: 'label', operator: Operators::INCLUDES_ALL, value: %w[tag1 tag2 tag3] }

          expect(condition_tree_parser.from_plain_object(collection_category, filters))
            .to have_attributes(field: filters[:field], operator: filters[:operator], value: %w[tag1 tag2 tag3])
        end
      end
    end
  end
end
