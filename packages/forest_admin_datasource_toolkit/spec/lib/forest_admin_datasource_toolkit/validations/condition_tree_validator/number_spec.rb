require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Validations
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Exceptions
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes
    describe ConditionTreeValidator do
      describe 'when the field is a number' do
        let(:collection) do
          build_collection({
                             schema: {
                               fields: {
                                 'number_field' => ColumnSchema.new(
                                   column_type: 'Number',
                                   filter_operators: [Operators::IN]
                                 )
                               }
                             }
                           })
        end

        it 'not raise an error when it using the In operator with an empty array' do
          condition_tree = ConditionTreeLeaf.new('number_field', Operators::IN, [])

          expect(described_class.validate(condition_tree, collection)).to be_nil
        end

        it 'not raise an error when it using the In operator with null value in an array' do
          condition_tree = ConditionTreeLeaf.new('number_field', Operators::IN, [nil])

          expect(described_class.validate(condition_tree, collection)).to be_nil
        end

        it 'not raise an error when using not_equal operator with a string number' do
          collection_with_not_equal = build_collection({
                                                         schema: {
                                                           fields: {
                                                             'id' => ColumnSchema.new(
                                                               column_type: 'Number',
                                                               filter_operators: [Operators::NOT_EQUAL]
                                                             )
                                                           }
                                                         }
                                                       })
          condition_tree = ConditionTreeLeaf.new('id', Operators::NOT_EQUAL, '27')

          expect(described_class.validate(condition_tree, collection_with_not_equal)).to be_nil
        end

        it 'not raise an error when using equal operator with a string number' do
          collection_with_equal = build_collection({
                                                     schema: {
                                                       fields: {
                                                         'id' => ColumnSchema.new(
                                                           column_type: 'Number',
                                                           filter_operators: [Operators::EQUAL]
                                                         )
                                                       }
                                                     }
                                                   })
          condition_tree = ConditionTreeLeaf.new('id', Operators::EQUAL, '42')

          expect(described_class.validate(condition_tree, collection_with_equal)).to be_nil
        end

        context 'with comparison operators' do
          let(:collection_with_comparisons) do
            build_collection({
                               schema: {
                                 fields: {
                                   'id' => ColumnSchema.new(
                                     column_type: 'Number',
                                     filter_operators: [
                                       Operators::GREATER_THAN,
                                       Operators::LESS_THAN,
                                       Operators::GREATER_THAN_OR_EQUAL,
                                       Operators::LESS_THAN_OR_EQUAL
                                     ]
                                   )
                                 }
                               }
                             })
          end

          it 'not raise an error when using greater_than operator with a string number' do
            condition_tree = ConditionTreeLeaf.new('id', Operators::GREATER_THAN, '100')

            expect(described_class.validate(condition_tree, collection_with_comparisons)).to be_nil
          end

          it 'not raise an error when using less_than operator with a string number' do
            condition_tree = ConditionTreeLeaf.new('id', Operators::LESS_THAN, '50')

            expect(described_class.validate(condition_tree, collection_with_comparisons)).to be_nil
          end

          it 'not raise an error when using greater_than_or_equal operator with a string number' do
            condition_tree = ConditionTreeLeaf.new('id', Operators::GREATER_THAN_OR_EQUAL, '75')

            expect(described_class.validate(condition_tree, collection_with_comparisons)).to be_nil
          end

          it 'not raise an error when using less_than_or_equal operator with a string number' do
            condition_tree = ConditionTreeLeaf.new('id', Operators::LESS_THAN_OR_EQUAL, '25')

            expect(described_class.validate(condition_tree, collection_with_comparisons)).to be_nil
          end
        end
      end
    end
  end
end
