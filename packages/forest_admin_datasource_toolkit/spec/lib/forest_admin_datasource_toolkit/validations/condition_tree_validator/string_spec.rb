require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Validations
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Exceptions
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes
    describe ConditionTreeValidator do
      describe 'when the field is a string' do
        it 'not raise an error when it using the ShorterThan operator' do
          collection = build_collection({
                                          schema: {
                                            fields: {
                                              'string_field' => ColumnSchema.new(
                                                column_type: 'String',
                                                filter_operators: [Operators::SHORTER_THAN]
                                              )
                                            }
                                          }
                                        })
          condition_tree = ConditionTreeLeaf.new('string_field', Operators::SHORTER_THAN, 10)

          expect(described_class.validate(condition_tree, collection)).to be_nil
        end

        it 'not raise an error when it using the LongerThan operator' do
          collection = build_collection({
                                          schema: {
                                            fields: {
                                              'string_field' => ColumnSchema.new(
                                                column_type: 'String',
                                                filter_operators: [Operators::LONGER_THAN]
                                              )
                                            }
                                          }
                                        })
          condition_tree = ConditionTreeLeaf.new('string_field', Operators::LONGER_THAN, 10)

          expect(described_class.validate(condition_tree, collection)).to be_nil
        end

        it 'not raise an error when it using the In operator with an empty array' do
          collection = build_collection({
                                          schema: {
                                            fields: {
                                              'string_field' => ColumnSchema.new(
                                                column_type: 'String',
                                                filter_operators: [Operators::IN]
                                              )
                                            }
                                          }
                                        })
          condition_tree = ConditionTreeLeaf.new('string_field', Operators::IN, [])

          expect(described_class.validate(condition_tree, collection)).to be_nil
        end

        it 'not raise an error when using GreaterThan operator with a numeric value on a string field' do
          collection = build_collection({
                                          schema: {
                                            fields: {
                                              'string_field' => ColumnSchema.new(
                                                column_type: 'String',
                                                filter_operators: [Operators::GREATER_THAN]
                                              )
                                            }
                                          }
                                        })
          condition_tree = ConditionTreeLeaf.new('string_field', Operators::GREATER_THAN, 42)

          expect(described_class.validate(condition_tree, collection)).to be_nil
        end

        it 'not raise an error when using LessThan operator with a numeric value on a string field' do
          collection = build_collection({
                                          schema: {
                                            fields: {
                                              'string_field' => ColumnSchema.new(
                                                column_type: 'String',
                                                filter_operators: [Operators::LESS_THAN]
                                              )
                                            }
                                          }
                                        })
          condition_tree = ConditionTreeLeaf.new('string_field', Operators::LESS_THAN, 42)

          expect(described_class.validate(condition_tree, collection)).to be_nil
        end
      end
    end
  end
end
