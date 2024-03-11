require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Validations
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Exceptions
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes
    describe ConditionTreeValidator do
      describe 'when the field is a boolean' do
        it 'not raise an error when it using the In operator with an empty array' do
          collection = collection_build({
                                          schema: {
                                            fields: {
                                              'a_boolean_field' => ColumnSchema.new(column_type: 'Boolean', filter_operators: [Operators::IN])
                                            }
                                          }
                                        })
          condition_tree = ConditionTreeLeaf.new('a_boolean_field', Operators::IN, [])

          expect(described_class.validate(condition_tree, collection)).to be_nil
        end
      end
    end
  end
end
