require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Validations
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Exceptions
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes
    describe ConditionTreeValidator do
      describe 'when the field is a JSON' do
        let(:collection) do
          collection_build({
                             schema: {
                               fields: {
                                 'json_field' => ColumnSchema.new(
                                   column_type: 'Json',
                                   filter_operators: [Operators::IN]
                                 )
                               }
                             }
                           })
        end

        it 'not raise an error when a list of json is given' do
          condition_tree = ConditionTreeLeaf.new('json_field', Operators::IN, %w[item1 item2])

          expect(described_class.validate(condition_tree, collection)).to be_nil
        end

        it 'not raise an error when an empty list of json is given' do
          condition_tree = ConditionTreeLeaf.new('json_field', Operators::IN, [])

          expect(described_class.validate(condition_tree, collection)).to be_nil
        end
      end
    end
  end
end
