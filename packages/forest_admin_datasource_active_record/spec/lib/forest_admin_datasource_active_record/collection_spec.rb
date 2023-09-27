require 'spec_helper'

module ForestAdminDatasourceActiveRecord
  describe Collection do
    let(:collection) do
      datasource = Datasource.new(adapter: 'sqlite3', database: 'db/database.db')
      described_class.new(datasource, Car)
    end

    describe 'fetch_fields' do
      it 'add all fields of model to the collection' do
        expect(collection.fields.keys).to include(
          'id',
          'category_id',
          'reference',
          'model',
          'brand',
          'year',
          'nb_seats',
          'is_manual',
          'options',
          'created_at',
          'updated_at'
        )
      end
    end
    describe 'fetch_associations' do
      it 'add all relation of model to the collection' do
        expect(collection.fields.keys).to include('category', 'user', 'car_checks', 'checks')
      end
    end
  end
end
