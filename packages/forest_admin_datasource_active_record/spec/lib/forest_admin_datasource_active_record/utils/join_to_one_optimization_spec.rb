require 'spec_helper'

module ForestAdminDatasourceActiveRecord
  include ForestAdminDatasourceToolkit::Schema
  include ForestAdminDatasourceToolkit::Components::Query

  describe 'to-one JOIN optimization', :db_truncation do
    let(:datasource) { Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' }) }
    let(:caller) { nil }
    let(:filter) { Filter.new }

    before do
      Account.delete_all
      Supplier.delete_all
      AccountHistory.delete_all
      Check.delete_all
      Car.unscoped.delete_all
      Category.delete_all

      history  = AccountHistory.create!
      supplier = Supplier.create!(name: 'ACME')
      Account.create!(supplier: supplier, account_history: history)

      category = Category.create!(label: 'Compact')
      car = Car.unscoped.create!(reference: 'CAR11', category: category) # id > 10 to pass Car's default_scope
      car.checks << Check.create!(garage_name: 'Garage1', date: Date.today)
    end

    def capture_sql
      queries = []
      sub = ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
        payload = args.last
        unless payload[:name] == 'SCHEMA' || payload[:name] == 'CACHE' ||
               payload[:sql] =~ /^(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i
          queries << payload[:sql]
        end
      end
      yield
      queries
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end

    describe 'a two-hop to-one chain (supplier -> account -> account_history)' do
      let(:collection) { Collection.new(datasource, Supplier) }
      let(:projection) { Projection.new(['id', 'name', 'account:id', 'account:account_history:id']) }

      it 'resolves the whole chain in ONE JOINed query (was 3 with preload)' do
        queries = capture_sql do
          result = collection.list(caller, filter, projection)
          expect(result.first['account']).not_to be_nil
          expect(result.first['account']['account_history']).not_to be_nil
        end

        expect(queries.size).to eq(1)
        expect(queries.first.scan(/LEFT OUTER JOIN/i).size).to eq(2)
      end

      it 'selects ONLY the projected columns of the joined tables (not table.*)' do
        query = Utils::Query.new(collection, projection, filter)
        query.build
        sql = query.query.to_sql

        expect(query.query.eager_load_values).to be_empty # eager_load would force account_histories.*
        AccountHistory.column_names.reject { |c| c == 'id' }.each do |col|
          expect(sql).not_to match(/account_histories"\."#{col}"/)
        end
      end

      it 'keeps a constant query count regardless of the number of rows' do
        5.times { |i| Account.create!(supplier: Supplier.create!(name: "S#{i}"), account_history: AccountHistory.create!) }

        two = capture_sql { collection.list(caller, Filter.new(page: Page.new(limit: 2, offset: 0)), projection) }
        all = capture_sql { collection.list(caller, filter, projection) }

        expect(two.size).to eq(all.size)
        expect(all.size).to eq(1)
      end
    end

    describe 'safety guard: a target with a default_scope falls back to preload' do
      let(:collection) { Collection.new(datasource, Car) }
      let(:projection) { Projection.new(['id', 'reference', 'category:label']) }

      # Car's default_scope has an unqualified column; a JOIN would raise "ambiguous column name".
      it 'does not JOIN and still returns correct data' do
        query = Utils::Query.new(collection, projection, filter)
        query.build

        result = collection.list(caller, filter, projection)
        expect(result.first['category']['label']).to eq('Compact')
      end
    end

    describe 'safety guard (belt-and-suspenders): target not local to this datasource' do
      let(:collection) { Collection.new(datasource, Account) }
      let(:query) { Utils::Query.new(collection, Projection.new(['id', 'supplier:name']), filter) }

      it 'returns nil when the collection name is absent (get_collection raises)' do
        expect { datasource.get_collection('NotInThisDatasource') }.to raise_error(StandardError)
        expect(query.send(:local_ar_collection, datasource, 'NotInThisDatasource')).to be_nil
      end

      it 'returns nil when the resolved collection is not ActiveRecord-backed' do
        # a Toolkit collection that is not our AR subclass, i.e. an RPC/Mongoid collection
        non_ar = instance_double(ForestAdminDatasourceToolkit::Collection)
        foreign_ds = instance_double(Datasource, get_collection: non_ar)

        expect(query.send(:local_ar_collection, foreign_ds, 'X')).to be_nil
      end

      it 'returns nil when the resolved AR collection belongs to a DIFFERENT datasource' do
        other_datasource = Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' })
        foreign_collection = Collection.new(other_datasource, Supplier)
        foreign_ds = instance_double(Datasource, get_collection: foreign_collection)

        expect(foreign_collection).to be_a(Collection) # AR-backed, so only identity can reject it
        expect(query.send(:local_ar_collection, foreign_ds, 'Supplier')).to be_nil
      end

      it 'fully_joinable? is false when the target cannot be resolved locally' do
        allow(query).to receive(:local_ar_collection).and_return(nil)
        expect(collection.schema[:fields]['supplier'].type).to eq('ManyToOne') # joinable but for the stub
        expect(query.send(:fully_joinable?, collection, 'supplier', Projection.new([]))).to be(false)
      end
    end

    describe 'a to-many relation (car -> checks) is left on preload' do
      let(:collection) { Collection.new(datasource, Car) }
      let(:projection) { Projection.new(['id', 'reference', 'checks:garage_name']) }

      it 'keeps preload (separate batched query), never a row-multiplying JOIN' do
        query = Utils::Query.new(collection, projection, filter)
        query.build

        expect(query.query.includes_values.to_s).to include('checks')
        expect(query.query.eager_load_values).to be_empty

        result = collection.list(caller, filter, projection)
        expect(result.first['checks'].first['garage_name']).to eq('Garage1')
      end
    end
  end
end
