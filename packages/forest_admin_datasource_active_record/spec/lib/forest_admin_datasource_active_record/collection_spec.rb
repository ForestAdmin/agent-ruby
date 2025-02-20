require 'spec_helper'

module ForestAdminDatasourceActiveRecord
  describe Collection do
    context 'without polymorphic support' do
      let(:datasource) { Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' }) }
      let(:collection) do
        described_class.new(datasource, Car)
      end

      describe 'fetch_fields' do
        it 'add all fields of model to the collection' do
          expect(collection.schema[:fields].keys).to include(
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
          expect(collection.schema[:fields].keys).to include('category', 'user', 'car_checks', 'checks')
        end

        it 'do not add polymorphic relations' do
          expect(datasource.get_collection('User').schema[:fields].keys).not_to include('address')
          expect(datasource.get_collection('Address').schema[:fields].keys).not_to include('addressable')
        end

        it 'add has_and_belongs_to_many relation' do
          collection = described_class.new(datasource, Company)

          expect(collection.schema[:fields].keys).to include('users')
        end
      end
    end

    context 'with polymorphic support' do
      let(:datasource) do
        Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' }, support_polymorphic_relations: true)
      end
      let(:collection) do
        described_class.new(datasource, Car)
      end

      describe 'fetch_associations' do
        it 'add polymorphic relations' do
          expect(datasource.get_collection('User').schema[:fields].keys).to include('address')
          expect(datasource.get_collection('Address').schema[:fields].keys).to include('addressable')
        end
      end
    end
  end
end
