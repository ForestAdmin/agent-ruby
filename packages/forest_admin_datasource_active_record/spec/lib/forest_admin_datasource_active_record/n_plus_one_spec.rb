require 'spec_helper'

module ForestAdminDatasourceActiveRecord
  include ForestAdminDatasourceToolkit::Schema
  include ForestAdminDatasourceToolkit::Components::Query

  describe 'N+1 Query Prevention' do
    let(:datasource) { Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' }) }
    let(:caller) { nil }
    let(:filter) { Filter.new }

    before do
      # Create test data
      category = Category.create!(label: 'Test Category')
      @car1 = Car.unscoped.create!(reference: 'CAR1', category: category)
      @car2 = Car.unscoped.create!(reference: 'CAR2', category: category)

      @user1 = User.create!(first_name: 'Alice', last_name: 'Smith', car: @car1)
      @user2 = User.create!(first_name: 'Bob', last_name: 'Jones', car: @car2)

      @check1 = Check.create!(garage_name: 'Check1', date: Date.today)
      @check2 = Check.create!(garage_name: 'Check2', date: Date.today)

      @car1.checks << @check1
      @car2.checks << @check2
    end

    def count_queries
      queries = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
        payload = args.last
        # Skip SCHEMA, CACHE, and transaction queries
        unless payload[:name] == 'SCHEMA' || payload[:name] == 'CACHE' ||
               payload[:sql] =~ /^(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i
          queries << payload[:sql]
        end
      end

      yield

      ActiveSupport::Notifications.unsubscribe(subscriber)
      queries.size
    end

    describe 'Car collection with belongs_to relation' do
      let(:collection) { Collection.new(datasource, Car) }

      it 'executes minimal queries for simple fields' do
        projection = Projection.new(['id', 'reference'])

        query_count = count_queries do
          collection.list(caller, filter, projection)
        end

        # Should be 1 query for cars
        expect(query_count).to be <= 2
      end

      it 'eager-loads belongs_to relation without N+1' do
        projection = Projection.new(['id', 'reference', 'category:label'])

        query_count = count_queries do
          result = collection.list(caller, filter, projection)
          # Verify data is accessible
          expect(result.first['category']).to have_key('label')
        end

        # Should be 2 queries: 1 for cars + 1 for categories
        expect(query_count).to be <= 2
      end

      it 'eager-loads has_many relation without N+1' do
        projection = Projection.new(['id', 'reference', 'checks:garage_name'])

        query_count = count_queries do
          result = collection.list(caller, filter, projection)
          # Verify data is accessible and is an array
          expect(result.first['checks']).to be_an(Array)
          expect(result.first['checks'].first).to have_key('garage_name') if result.first['checks'].any?
        end

        # Should be 3 queries: 1 for cars + 1 for car_checks join table + 1 for checks
        expect(query_count).to be <= 3
      end

      it 'maintains constant query count regardless of record count' do
        # Add more test data
        10.times do |i|
          car = Car.unscoped.create!(reference: "CAR#{i + 3}", category: @car1.category)
          User.create!(first_name: "User#{i}", last_name: 'Test', car: car)
        end

        projection = Projection.new(['id', 'reference', 'category:label'])

        # Query with 2 records
        filter_two = Filter.new(page: Page.new(limit: 2, offset: 0))
        queries_for_two = count_queries do
          collection.list(caller, filter_two, projection)
        end

        # Query with all records
        queries_for_all = count_queries do
          collection.list(caller, filter, projection)
        end

        # Query count should be the same (eager loading prevents N+1)
        expect(queries_for_two).to eq(queries_for_all)
      end
    end

    describe 'verification that eager loading is applied' do
      let(:collection) { Collection.new(datasource, Car) }

      it 'includes associations are added to the query' do
        projection = Projection.new(['id', 'reference', 'category:label', 'checks:garage_name'])
        query = Utils::Query.new(collection, projection, filter)

        # Build the query to apply includes
        query.build

        # Check that includes are present in the query
        # ActiveRecord's includes_values should contain our associations
        includes_values = query.query.includes_values
        expect(includes_values).not_to be_empty

        # The format should include category and checks
        expect(includes_values.to_s).to include('category').or include('checks')
      end
    end
  end
end
