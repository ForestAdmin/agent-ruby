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

      describe 'filter operators' do
        context 'when using BLANK operator' do
          context 'with a String field' do
            it 'filters records where field is NULL or empty string' do
              condition_tree = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf.new('brand', ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::BLANK, nil)
              filter = Filter.new(condition_tree: condition_tree)
              query_builder = described_class.new(collection, nil, filter)
              query_builder.build

              sql = query_builder.query.to_sql
              expect(sql).to match(/"cars"\."brand" = '' OR "cars"\."brand" IS NULL/)
            end
          end

          context 'with a non-String field' do
            it 'filters records where field is NULL' do
              condition_tree = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf.new('year', ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::BLANK, nil)
              filter = Filter.new(condition_tree: condition_tree)
              query_builder = described_class.new(collection, nil, filter)
              query_builder.build

              expect(query_builder.query.to_sql).to include('"cars"."year" IS NULL')
            end
          end
        end

        context 'when using MISSING operator' do
          it 'filters records where field is NULL' do
            condition_tree = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf.new('brand', ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::MISSING, nil)
            filter = Filter.new(condition_tree: condition_tree)
            query_builder = described_class.new(collection, nil, filter)
            query_builder.build

            expect(query_builder.query.to_sql).to include('"cars"."brand" IS NULL')
          end
        end

        context 'when using PRESENT operator' do
          context 'with a String field' do
            it 'filters records where field is NOT NULL and not empty string' do
              condition_tree = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf.new('brand', ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::PRESENT, nil)
              filter = Filter.new(condition_tree: condition_tree)
              query_builder = described_class.new(collection, nil, filter)
              query_builder.build

              sql = query_builder.query.to_sql
              expect(sql).to match(/NOT \(\("cars"\."brand" = '' OR "cars"\."brand" IS NULL\)\)/)
            end
          end

          context 'with a non-String field' do
            it 'filters records where field is NOT NULL' do
              condition_tree = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf.new('year', ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::PRESENT, nil)
              filter = Filter.new(condition_tree: condition_tree)
              query_builder = described_class.new(collection, nil, filter)
              query_builder.build

              expect(query_builder.query.to_sql).to include('"cars"."year" IS NOT NULL')
            end
          end
        end
      end
    end
  end
end
