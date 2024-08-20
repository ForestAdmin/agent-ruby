require 'spec_helper'

module ForestAdminDatasourceActiveRecord
  module Utils
    include ForestAdminDatasourceToolkit::Components::Query

    describe Query do
      let(:datasource) { Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' }) }
      let(:collection) { Collection.new(datasource, Car) }

      it 'unscoped the active record query' do
        query_builder = described_class.new(collection, Projection.new, Filter.new)

        # default scope set on Car model: default_scope { where('id > ?', 10) }
        expect(query_builder.query.to_sql).not_to eq(Car.where('id > ?', 10).to_sql)
        expect(query_builder.query.to_sql).to eq('SELECT "cars".* FROM "cars"')
      end
    end
  end
end
