require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Validations
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Exceptions
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes
    describe ConditionTreeValidator do
      describe 'when the field is a Point' do
        let(:collection) do
          collection_build({
                             schema: {
                               fields: {
                                 'point_field' => ColumnSchema.new(
                                   column_type: 'Point',
                                   filter_operators: [Operators::EQUAL]
                                 )
                               }
                             }
                           })
        end

        it 'not raise an error when the filter value is well formatted' do
          condition_tree = ConditionTreeLeaf.new('point_field', Operators::EQUAL, '-80,20')

          expect(described_class.validate(condition_tree, collection)).to be_nil
        end

        describe 'when the field value is not well formatted' do
          it 'raise an error' do
            condition_tree = ConditionTreeLeaf.new('point_field', Operators::EQUAL, '-80, 20, 90')

            expect do
              described_class.validate(condition_tree, collection)
            end.to raise_error(Exceptions::ValidationError)
          end
        end
      end
    end
  end
end
