require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Validations
    include ForestAdminDatasourceToolkit::Exceptions
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Components::Query

    describe ProjectionValidator do
      before do
        @datasource = Datasource.new
        @collection = Collection.new(@datasource, 'owner')
        @collection.add_fields(
          {
            'id' => ColumnSchema.new(column_type: Concerns::PrimitiveTypes::NUMBER, is_primary_key: true),
            'name' => ColumnSchema.new(column_type: Concerns::PrimitiveTypes::STRING),
            'address' => Relations::OneToOneSchema.new(
              origin_key: 'id',
              origin_key_target: 'id',
              foreign_collection: 'address'
            )
          }
        )

        @datasource.add_collection(@collection)
      end

      it 'don\'t throws if the field exist on the collection' do
        expect(described_class.validate?(@collection, Projection.new(['name']))).to eq(['name'])
      end

      it 'throws if the field does not exist on the collection' do
        expect do
          described_class.validate?(@collection, Projection.new(['__not_defined']))
        end.to raise_error(ValidationError, "🌳🌳🌳 Column not found: 'owner.__not_defined'")
      end
    end
  end
end
