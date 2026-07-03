require 'spec_helper'

module ForestAdminDatasourceActiveRecord
  include ForestAdminDatasourceToolkit::Schema
  include ForestAdminDatasourceToolkit::Components::Query

  describe 'belongs_to JOIN optimization', :db_truncation do
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

      supplier = Supplier.create!(name: 'ACME')
      Account.create!(supplier: supplier, account_history: AccountHistory.create!)

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

    describe 'a belongs_to relation (account -> supplier)' do
      let(:collection) { Collection.new(datasource, Account) }
      let(:projection) { Projection.new(['id', 'supplier:name']) }

      it 'resolves it in ONE JOINed query (was 2 with preload)' do
        queries = capture_sql do
          result = collection.list(caller, filter, projection)
          expect(result.first['supplier']['name']).to eq('ACME')
        end

        expect(queries.size).to eq(1)
        expect(queries.first.scan(/LEFT OUTER JOIN/i).size).to eq(1)
      end

      it 'selects ONLY the projected columns of the joined table (not table.*)' do
        query = Utils::Query.new(collection, projection, filter)
        query.build
        sql = query.query.to_sql

        expect(query.query.eager_load_values).to be_empty # eager_load would force suppliers.*
        selected = %w[id name]
        Supplier.column_names.reject { |c| selected.include?(c) }.each do |col|
          expect(sql).not_to match(/suppliers"\."#{col}"/)
        end
      end

      it 'keeps a constant query count regardless of the number of rows' do
        5.times { Account.create!(supplier: Supplier.create!(name: 'S'), account_history: AccountHistory.create!) }

        two = capture_sql { collection.list(caller, Filter.new(page: Page.new(limit: 2, offset: 0)), projection) }
        all = capture_sql { collection.list(caller, filter, projection) }

        expect(two.size).to eq(all.size)
        expect(all.size).to eq(1)
      end
    end

    describe 'a has_one relation (supplier -> account) is left on preload' do
      # has_one does not guarantee a single child row; a JOIN could duplicate the parent.
      let(:collection) { Collection.new(datasource, Supplier) }
      let(:projection) { Projection.new(['id', 'name', 'account:id']) }

      it 'is preloaded, not JOINed' do
        query = Utils::Query.new(collection, projection, filter)
        query.build

        expect(query.query.left_outer_joins_values).to be_empty
        expect(query.query.includes_values.to_s).to include('account')
        expect(query.joined_relations).to be_empty
      end
    end

    describe 'a related record exposes the same columns whether JOINed or preloaded' do
      it 'returns exactly the projected columns for a JOINed to-one (account -> supplier)' do
        result = Collection.new(datasource, Account).list(caller, filter, Projection.new(['id', 'supplier:name']))
        expect(result.first['supplier'].keys).to contain_exactly('name')
      end

      it 'returns exactly the projected columns for a preloaded to-one (supplier -> account)' do
        # supplier -> account is a has_one, so it is preloaded; it must still be projected-restricted
        result = Collection.new(datasource, Supplier).list(caller, filter, Projection.new(['id', 'account:id']))
        expect(result.first['account'].keys).to contain_exactly('id')
      end
    end

    describe 'a has_one :through of belongs_to hops (account -> account_history -> order)' do
      let(:collection) { Collection.new(datasource, Account) }
      let(:projection) { Projection.new(['id', 'order:reference']) }

      before do
        order = Order.create!(reference: 'ORD-1')
        Account.first.account_history.update!(order: order)
      end

      it 'folds the whole chain into ONE JOINed query (was 3 with per-hop preload)' do
        queries = capture_sql do
          result = collection.list(caller, filter, projection)
          expect(result.first['order']['reference']).to eq('ORD-1')
        end

        expect(queries.size).to eq(1)
        expect(queries.first.scan(/LEFT OUTER JOIN/i).size).to eq(2)
      end

      it 'filters on a field of the through relation' do
        condition = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
                    .new('order:reference', 'Equal', 'ORD-1')
        result = collection.list(caller, Filter.new(condition_tree: condition), projection)

        expect(result.size).to eq(1)
        expect(result.first['order']['reference']).to eq('ORD-1')
      end

      it 'returns nothing when the through relation value does not match' do
        condition = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
                    .new('order:reference', 'Equal', 'NOPE')
        result = collection.list(caller, Filter.new(condition_tree: condition), Projection.new(['id']))

        expect(result).to be_empty
      end

      it 'aggregates grouped by a field of the through relation' do
        aggregation = Aggregation.new(operation: 'Count', field: nil, groups: [{ field: 'order:reference' }])
        result = Utils::QueryAggregate.new(collection, aggregation).get

        expect(result).to contain_exactly('value' => 1, 'group' => { 'order:reference' => 'ORD-1' })
      end

      it 'does not JOIN the intermediate table twice when it is also projected on its own' do
        projection = Projection.new(['id', 'order:reference', 'account_history:id'])
        query = Utils::Query.new(collection, projection, filter)
        query.build

        expect(query.query.to_sql.scan(/JOIN "account_histories"/i).size).to eq(1)

        result = collection.list(caller, filter, projection)
        expect(result.first['order']['reference']).to eq('ORD-1')
        expect(result.first['account_history']['id']).to eq(Account.first.account_history_id)
      end

      it 'does not JOIN the intermediate table twice when a filter already joined the through' do
        projection = Projection.new(['id', 'account_history:id'])
        condition = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
                    .new('order:reference', 'Equal', 'ORD-1')
        query = Utils::Query.new(collection, projection, Filter.new(condition_tree: condition))
        query.build

        expect(query.query.to_sql.scan(/JOIN "account_histories"/i).size).to eq(1)

        result = collection.list(caller, Filter.new(condition_tree: condition), projection)
        expect(result.first['account_history']['id']).to eq(Account.first.account_history_id)
      end

      it 'reuses the intermediate join when a plain belongs_to shares the same signature (one query)' do
        projection = Projection.new(['id', 'order:reference', 'account_history:id'])
        query = Utils::Query.new(collection, projection, filter)
        query.build

        expect(query.query.to_sql.scan(/JOIN "account_histories"/i).size).to eq(1)
        expect(query.query.includes_values).to be_empty
      end

      it 'preloads a belongs_to that would alias the through intermediate (same table, different FK)' do
        projection = Projection.new(['id', 'order:reference', 'secondary_history:id'])
        query = Utils::Query.new(collection, projection, filter)
        query.build

        expect(query.query.to_sql.scan(/JOIN "account_histories"/i).size).to eq(1)
        expect(query.query.includes_values.to_s).to include('secondary_history')
      end
    end

    describe 'a has_one :through with a has_one hop (supplier -> account_history) stays on preload' do
      let(:collection) { Collection.new(datasource, Supplier) }
      let(:projection) { Projection.new(['id', 'account_history:id']) }

      it 'is preloaded, not JOINed' do
        query = Utils::Query.new(collection, projection, filter)
        query.build

        expect(query.query.left_outer_joins_values).to be_empty
        expect(query.query.includes_values.to_s).to include('account_history')
      end

      it 'does not select the intermediate FK against the root table (it lives on the child)' do
        query = Utils::Query.new(collection, projection, filter)
        query.build
        sql = query.query.to_sql

        expect(sql).not_to match(/suppliers"\."supplier_id"/)
        expect(sql).not_to match(/suppliers"\."account_id"/)
        expect { collection.list(caller, filter, projection) }.not_to raise_error
      end
    end

    describe 'a to-many relation (car -> checks) is left on preload' do
      let(:collection) { Collection.new(datasource, Car) }
      let(:projection) { Projection.new(['id', 'reference', 'checks:garage_name']) }

      it 'keeps preload (separate batched query), never a row-multiplying JOIN' do
        query = Utils::Query.new(collection, projection, filter)
        query.build

        expect(query.query.includes_values.to_s).to include('checks')
        expect(query.query.left_outer_joins_values).to be_empty

        result = collection.list(caller, filter, projection)
        expect(result.first['checks'].first['garage_name']).to eq('Garage1')
      end
    end

    describe 'safety guard: a target with a default_scope falls back to preload' do
      # Car (the target here) has a default_scope with an unqualified column; a JOIN would raise
      # "ambiguous column name", so user -> car must stay on preload.
      let(:collection) { Collection.new(datasource, User) }
      let(:projection) { Projection.new(['id', 'car:reference']) }

      it 'does not JOIN the scoped target' do
        query = Utils::Query.new(collection, projection, filter)
        query.build

        expect(query.joined_relations).to be_empty
        expect(query.query.left_outer_joins_values).to be_empty
        expect(query.query.includes_values.to_s).to include('car')
      end
    end

    describe 'safety guard: a scoped belongs_to falls back to preload' do
      # belongs_to :x, -> { ... } applies its scope to the JOIN (unqualified SQL / extra joins).
      let(:collection) { Collection.new(datasource, Account) }
      let(:query) { Utils::Query.new(collection, Projection.new(['id', 'supplier:name']), filter) }

      it 'does not JOIN an association that carries a scope' do
        scoped = Account.reflect_on_association(:supplier)
        allow(scoped).to receive(:scope).and_return(-> { where('id > 0') })
        allow(Account).to receive(:reflect_on_association).and_return(scoped)

        expect(query.send(:joinable_target, collection, 'supplier')).to be_nil
      end
    end

    describe 'safety guard: a table already present in the query is not joined with a different signature' do
      # ActiveRecord reuses a join with the same ON condition, but aliases one with a different
      # condition; collect_joined_selects cannot reference that alias, so a conflicting relation
      # must fall back to preload.
      let(:collection) { Collection.new(datasource, Account) }
      let(:query) { Utils::Query.new(collection, Projection.new(['id', 'supplier:name']), filter) }

      it 'reuses the join for a matching signature and bails on a conflicting one' do
        joinable = query.send(:joinable_joins, collection, 'supplier', Projection.new(['name']), { 'accounts' => :root })
        expect(joinable).to eq('suppliers' => 'accounts.supplier_id->suppliers')

        reused = query.send(:joinable_joins, collection, 'supplier', Projection.new(['name']),
                            { 'accounts' => :root, 'suppliers' => 'accounts.supplier_id->suppliers' })
        expect(reused).to eq('suppliers' => 'accounts.supplier_id->suppliers') # same signature -> reused, not aliased

        conflicting = query.send(:joinable_joins, collection, 'supplier', Projection.new(['name']),
                                 { 'accounts' => :root, 'suppliers' => 'account_histories.order_id->suppliers' })
        expect(conflicting).to be_nil # same target/FK from a different parent -> would alias
      end

      it 'scopes a signature by its source table so same target/FK from different parents differ' do
        # the through order hop joins orders FROM account_histories; a direct belongs_to :order would
        # join orders FROM accounts. Same FK name, same target -> must not share a signature.
        sigs = query.send(:join_signatures, collection, 'order')
        expect(sigs['orders']).to eq('account_histories.order_id->orders')
      end
    end

    describe 'safety guard: a relation already joined by a filter/sort is not joined again' do
      let(:collection) { Collection.new(datasource, Account) }
      let(:projection) { Projection.new(['id', 'supplier:name']) }

      it 'falls back to preload for a relation the filter already joined (no duplicate JOIN)' do
        condition = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
                    .new('supplier:name', 'Equal', 'ACME')
        filter = Filter.new(condition_tree: condition)

        query = Utils::Query.new(collection, projection, filter)
        query.build

        expect(query.joined_relations).to be_empty # supplier was already joined for the filter
        expect(query.query.to_sql.scan(/LEFT OUTER JOIN "suppliers"/i).size).to eq(1)

        result = collection.list(caller, filter, projection)
        expect(result.first['supplier']['name']).to eq('ACME')
      end
    end

    describe 'same_database?' do
      let(:query) { Utils::Query.new(Collection.new(datasource, Account), Projection.new(['id']), filter) }

      it 'compares connection pools' do
        model_a = Class.new { def self.connection_pool = :first_pool }
        model_b = Class.new { def self.connection_pool = :second_pool }

        expect(query.send(:same_database?, model_a, model_a)).to be(true)
        expect(query.send(:same_database?, model_a, model_b)).to be(false)
        expect(query.send(:same_database?, Account, Supplier)).to be(true)
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

      it 'joinable_joins is nil when the target cannot be resolved locally' do
        allow(query).to receive(:local_ar_collection).and_return(nil)
        expect(collection.schema[:fields]['supplier'].type).to eq('ManyToOne') # joinable but for the stub
        expect(query.send(:joinable_joins, collection, 'supplier', Projection.new([]), { 'accounts' => :root })).to be_nil
      end
    end
  end
end
