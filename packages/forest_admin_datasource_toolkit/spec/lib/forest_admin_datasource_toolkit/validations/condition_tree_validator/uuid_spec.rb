require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Validations
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Exceptions
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes
    describe ConditionTreeValidator do
      describe 'when the field is an UUID' do
        let(:collection) do
          build_collection({
                             schema: {
                               fields: {
                                 'uuid_field' => ColumnSchema.new(
                                   column_type: 'Uuid',
                                   filter_operators: [Operators::IN]
                                 )
                               }
                             }
                           })
        end

        it 'not raise an error when a list of uuid is given' do
          condition_tree = ConditionTreeLeaf.new(
            'uuid_field',
            Operators::IN,
            %w[2d162303-78bf-599e-b197-93590ac3d315 2d162303-78bf-599e-b197-93590ac3d315]
          )

          expect(described_class.validate(condition_tree, collection)).to be_nil
        end

        it 'not raise an error when an empty list of uuid is given' do
          condition_tree = ConditionTreeLeaf.new(
            'uuid_field',
            Operators::IN,
            []
          )

          expect(described_class.validate(condition_tree, collection)).to be_nil
        end

        it 'raise an error when at least one uuid is malformed' do
          condition_tree = ConditionTreeLeaf.new(
            'uuid_field',
            Operators::IN,
            %w[2d162303-78bf-599e-b197-93590ac3d315 malformed-2d162303-78bf-599e-b197-93590ac3d315]
          )

          expect do
            described_class.validate(condition_tree, collection)
          end.to raise_error(Exceptions::ValidationError)
        end
      end
    end
  end
end
