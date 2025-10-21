require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Validations
    include ForestAdminDatasourceToolkit
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Components::Query
    describe SortValidator do
      let(:collection_user) do
        datasource = Datasource.new
        collection = Collection.new(datasource, 'User')
        collection.add_fields(
          {
            'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                     filter_operators: [ConditionTree::Operators::EQUAL])
          }
        )

        return collection
      end

      it('does not throw if the field exist on the collection') do
        expect { described_class.validate(collection_user, Sort.new([{ field: 'id', ascending: true }])) }.not_to raise_error
      end

      it('throws if the field does not exist on the collection') do
        expect { described_class.validate(collection_user, Sort.new([{ field: '__no__such__field', ascending: true }])) }.to raise_error(
          ForestAdminDatasourceToolkit::Exceptions::ValidationError, "Column not found: 'User.__no__such__field'"
        )
      end

      context 'when parameter is a boolean' do
        it('does not throw if the ascending parameter is boolean') do
          expect { described_class.validate(collection_user, Sort.new([{ field: 'id', ascending: true }])) }.not_to raise_error
        end

        it('throws if the ascending parameter is not boolean') do
          expect { described_class.validate(collection_user, Sort.new([{ field: 'id', ascending: 42 }])) }.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ValidationError, 'Invalid sort_utils.ascending value: 42'
          )
        end
      end
    end
  end
end
