require 'spec_helper'

module ForestAdminDatasourceActiveRecord
  include ForestAdminDatasourceToolkit::Schema
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

        it 'add has_one_through relation' do
          collection = described_class.new(datasource, Supplier)

          expect(collection.schema[:fields].keys).to include('account_history')

          expect(collection.schema[:fields]['account_history'].class).to eq(Relations::ManyToManySchema)
        end
      end

      describe 'delete' do
        it 'uses delete_all for bulk deletion with a single SQL query' do
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
            condition_tree: ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf.new(
              'brand',
              ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::EQUAL,
              'Toyota'
            )
          )

          query_double = instance_spy(ActiveRecord::Relation)
          query_instance = instance_double(Utils::Query)
          allow(Utils::Query).to receive(:new).and_return(query_instance)
          allow(query_instance).to receive(:build).and_return(query_double)

          collection.delete(nil, filter)

          expect(query_double).to have_received(:delete_all)
        end

        it 'handles nil query gracefully' do
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new
          query_instance = instance_double(Utils::Query)
          allow(Utils::Query).to receive(:new).and_return(query_instance)
          allow(query_instance).to receive(:build).and_return(nil)

          expect { collection.delete(nil, filter) }.not_to raise_error
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
