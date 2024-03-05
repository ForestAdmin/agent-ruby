require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Query
      module Utils
        include ForestAdminDatasourceToolkit
        include ForestAdminDatasourceToolkit::Schema
        include ForestAdminDatasourceToolkit::Components::Query::SortUtils
        describe SortFactory do
          it 'returns a sort instance sorted by primary keys' do
            collection_with_composite_id = Collection.new(Datasource.new, 'Book')
            collection_with_composite_id.add_fields(
              {
                'id1' => ColumnSchema.new(column_type: PrimitiveType::UUID, is_primary_key: true),
                'id2' => ColumnSchema.new(column_type: PrimitiveType::UUID, is_primary_key: true)
              }
            )

            expect(described_class.by_primary_keys(collection_with_composite_id)).to eq([
                                                                                          { field: 'id1', ascending: true },
                                                                                          { field: 'id2', ascending: true }
                                                                                        ])
          end
        end
      end
    end
  end
end
