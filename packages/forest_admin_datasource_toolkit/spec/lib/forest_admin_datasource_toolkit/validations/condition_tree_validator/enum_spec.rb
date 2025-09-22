require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Validations
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Exceptions
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes
    describe ConditionTreeValidator do
      describe 'when the field is an enum' do
        it 'raise an error when the field value is not a valid enum' do
          collection = build_collection({
                                          schema: {
                                            fields: {
                                              'enum_field' => ColumnSchema.new(
                                                column_type: 'Enum',
                                                enum_values: ['allowed_value'],
                                                filter_operators: [Operators::EQUAL]
                                              )
                                            }
                                          }
                                        })
          condition_tree = ConditionTreeLeaf.new('enum_field', Operators::EQUAL, 'random')

          expect do
            described_class.validate(condition_tree, collection)
          end.to raise_error(
            Exceptions::ValidationError,
            '🌳🌳🌳 The given enum value(s) random is not listed in ["allowed_value"]'
          )
        end

        it 'raise an error when the at least one field value is not a valid enum' do
          collection = build_collection({
                                          schema: {
                                            fields: {
                                              'enum_field' => ColumnSchema.new(
                                                column_type: 'Enum',
                                                enum_values: ['allowed_value'],
                                                filter_operators: [Operators::IN]
                                              )
                                            }
                                          }
                                        })
          condition_tree = ConditionTreeLeaf.new('enum_field', Operators::IN, %w[random allowed_value])

          expect do
            described_class.validate(condition_tree, collection)
          end.to raise_error(
            Exceptions::ValidationError,
            '🌳🌳🌳 The given enum value(s) random is not listed in ["allowed_value"]'
          )
        end

        it 'not raise an error when all enum values are allowed' do
          collection = build_collection({
                                          schema: {
                                            fields: {
                                              'enum_field' => ColumnSchema.new(
                                                column_type: 'Enum',
                                                enum_values: %w[allowed_value other_allowed_value],
                                                filter_operators: [Operators::IN]
                                              )
                                            }
                                          }
                                        })
          condition_tree = ConditionTreeLeaf.new('enum_field', Operators::IN, %w[other_allowed_value allowed_value])

          expect(described_class.validate(condition_tree, collection)).to be_nil
        end

        it 'not raise an error when enum must be present' do
          collection = build_collection({
                                          schema: {
                                            fields: {
                                              'enum_field' => ColumnSchema.new(
                                                column_type: 'Enum',
                                                enum_values: %w[allowed_value other_allowed_value],
                                                filter_operators: [Operators::PRESENT]
                                              )
                                            }
                                          }
                                        })
          condition_tree = ConditionTreeLeaf.new('enum_field', Operators::PRESENT)

          expect(described_class.validate(condition_tree, collection)).to be_nil
        end
      end
    end
  end
end
