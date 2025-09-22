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

      describe 'build select' do
        context 'when projection have nested relation' do
          it 'build select with all requested fields related to the current collection' do
            projection = Projection.new(%w[account_history:account:id account_history:account_id account_history:id])
            collection = Collection.new(datasource, Account)
            query_builder = described_class.new(collection, projection, Filter.new)
            query_builder.build

            expect(query_builder.select).to eq(%w[accounts.account_history_id accounts.id])
          end
        end
      end
    end
  end
end
