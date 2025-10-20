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
        context 'when using CONTAINS operator' do
          it 'filters records where field contains value (case sensitive)' do
            condition_tree = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf.new('brand', ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::CONTAINS, 'test')
            filter = Filter.new(condition_tree: condition_tree)
            query_builder = described_class.new(collection, nil, filter)
            query_builder.build

            sql = query_builder.query.to_sql
            expect(sql).to include('"cars"."brand" LIKE \'%test%\'')
          end
        end

        context 'when using I_CONTAINS operator' do
          it 'filters records where field contains value (case insensitive)' do
            condition_tree = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf.new('brand', ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::I_CONTAINS, 'Test')
            filter = Filter.new(condition_tree: condition_tree)
            query_builder = described_class.new(collection, nil, filter)
            query_builder.build

            sql = query_builder.query.to_sql
            expect(sql).to include('LOWER("cars"."brand") LIKE \'%test%\'')
          end
        end

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

        context 'when using comparison operators on String fields' do
          context 'with numeric value' do
            it 'uses LENGTH() function for GREATER_THAN' do
              condition_tree = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf.new('brand', ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::GREATER_THAN, 10)
              filter = Filter.new(condition_tree: condition_tree)
              query_builder = described_class.new(collection, nil, filter)
              query_builder.build

              sql = query_builder.query.to_sql
              expect(sql).to include('LENGTH')
              expect(sql).to match(/LENGTH.*"brand".*>.*10/)
            end

            it 'uses LENGTH() function for LESS_THAN' do
              condition_tree = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf.new('brand', ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::LESS_THAN, 5)
              filter = Filter.new(condition_tree: condition_tree)
              query_builder = described_class.new(collection, nil, filter)
              query_builder.build

              sql = query_builder.query.to_sql
              expect(sql).to include('LENGTH')
              expect(sql).to match(/LENGTH.*"brand".*<.*5/)
            end

            it 'uses LENGTH() function for GREATER_THAN_OR_EQUAL' do
              condition_tree = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf.new('brand', ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::GREATER_THAN_OR_EQUAL, 15)
              filter = Filter.new(condition_tree: condition_tree)
              query_builder = described_class.new(collection, nil, filter)
              query_builder.build

              sql = query_builder.query.to_sql
              expect(sql).to include('LENGTH')
              expect(sql).to match(/LENGTH.*"brand".*>=.*15/)
            end

            it 'uses LENGTH() function for LESS_THAN_OR_EQUAL' do
              condition_tree = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf.new('brand', ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::LESS_THAN_OR_EQUAL, 20)
              filter = Filter.new(condition_tree: condition_tree)
              query_builder = described_class.new(collection, nil, filter)
              query_builder.build

              sql = query_builder.query.to_sql
              expect(sql).to include('LENGTH')
              expect(sql).to match(/LENGTH.*"brand".*<=.*20/)
            end

            it 'handles zero value correctly' do
              condition_tree = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf.new('brand', ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::GREATER_THAN, 0)
              filter = Filter.new(condition_tree: condition_tree)
              query_builder = described_class.new(collection, nil, filter)
              query_builder.build

              sql = query_builder.query.to_sql
              expect(sql).to include('LENGTH')
              expect(sql).to match(/LENGTH.*"brand".*>.*0/)
            end

            it 'handles float value correctly' do
              condition_tree = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf.new('brand', ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::GREATER_THAN, 10.5)
              filter = Filter.new(condition_tree: condition_tree)
              query_builder = described_class.new(collection, nil, filter)
              query_builder.build

              sql = query_builder.query.to_sql
              expect(sql).to include('LENGTH')
              expect(sql).to match(/LENGTH.*"brand".*>.*10\.5/)
            end
          end

          context 'with string value' do
            it 'uses lexicographic comparison for GREATER_THAN' do
              condition_tree = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf.new('brand', ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::GREATER_THAN, 'Toyota')
              filter = Filter.new(condition_tree: condition_tree)
              query_builder = described_class.new(collection, nil, filter)
              query_builder.build

              sql = query_builder.query.to_sql
              expect(sql).not_to include('LENGTH')
              expect(sql).to match(/"brand".*>.*'Toyota'/)
            end

            it 'uses lexicographic comparison for LESS_THAN' do
              condition_tree = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf.new('brand', ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::LESS_THAN, 'BMW')
              filter = Filter.new(condition_tree: condition_tree)
              query_builder = described_class.new(collection, nil, filter)
              query_builder.build

              sql = query_builder.query.to_sql
              expect(sql).not_to include('LENGTH')
              expect(sql).to match(/"brand".*<.*'BMW'/)
            end
          end
        end

        context 'when using comparison operators on Number fields' do
          it 'uses direct comparison without LENGTH() for GREATER_THAN' do
            condition_tree = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf.new('year', ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::GREATER_THAN, 2000)
            filter = Filter.new(condition_tree: condition_tree)
            query_builder = described_class.new(collection, nil, filter)
            query_builder.build

            sql = query_builder.query.to_sql
            expect(sql).not_to include('LENGTH')
            expect(sql).to match(/"year".*>.*2000/)
          end

          it 'uses direct comparison without LENGTH() for LESS_THAN' do
            condition_tree = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf.new('year', ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::LESS_THAN, 2020)
            filter = Filter.new(condition_tree: condition_tree)
            query_builder = described_class.new(collection, nil, filter)
            query_builder.build

            sql = query_builder.query.to_sql
            expect(sql).not_to include('LENGTH')
            expect(sql).to match(/"year".*<.*2020/)
          end
        end
      end
    end
  end
end
