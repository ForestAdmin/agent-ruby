module ForestAdminDatasourceIntercom
  # The in-memory tier is exercised through Admin, a real collection carrying one
  # column of each kind it has to handle: strings, booleans and a list.
  RSpec.describe Collections::FetchAllCollection do
    subject(:collection) { Collections::Admin.new(datasource) }

    let(:datasource) { Datasource.new(access_token: 's3cr3t', rate_limiter: nil) }
    let(:base) { datasource.configuration.url }
    let(:operators) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators }

    def leaf(field, operator, value = nil)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
        .new(field, operator, value)
    end

    def filter(condition_tree: nil, page: nil, sort: nil)
      ForestAdminDatasourceToolkit::Components::Query::Filter.new(condition_tree: condition_tree, page: page,
                                                                  sort: sort)
    end

    def page(offset, limit)
      ForestAdminDatasourceToolkit::Components::Query::Page.new(offset: offset, limit: limit)
    end

    def sort(*clauses)
      ForestAdminDatasourceToolkit::Components::Query::Sort.new(clauses)
    end

    def aggregation(operation, field: nil, groups: [])
      ForestAdminDatasourceToolkit::Components::Query::Aggregation.new(operation: operation, field: field,
                                                                       groups: groups)
    end

    def admin(id, overrides = {})
      { 'type' => 'admin', 'id' => id, 'name' => "Admin #{id}", 'email' => "#{id}@acme.test",
        'away_mode_enabled' => false, 'has_inbox_seat' => true, 'team_ids' => [] }.merge(overrides)
    end

    def stub_admins(*admins)
      stub_request(:get, "#{base}/admins")
        .to_return(status: 200, body: { 'type' => 'admin.list', 'admins' => admins }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    def ids(records)
      records.map { |record| record['id'] }
    end

    # An operator is evaluable in memory when `ConditionTreeLeaf#match` handles
    # it natively or the toolkit can rewrite it into operators that it does.
    def evaluable?(operator, column_type)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::ConditionTreeEquivalent
        .equivalent_tree?(operator, described_class::IN_MEMORY_OPERATORS, column_type)
    end

    # The count and the group are taken over every record Intercom holds, not
    # over a page of them, which is what makes them exact.
    it 'is countable' do
      expect(collection.is_countable?).to be(true)
    end

    describe 'columns' do
      it 'declares a scalar column filterable, sortable and groupable' do
        expect(collection.fields['name'])
          .to have_attributes(is_sortable: true, is_groupable: true)
        expect(collection.fields['name'].filter_operators).to include(operators::EQUAL)
      end

      # This lot writes nothing: an editable column would offer a Save that
      # reaches an `update` the collection does not implement.
      it 'declares every column read-only' do
        expect(collection.fields.values.map(&:is_read_only).uniq).to eq([true])
      end

      # A list has no in-memory counterpart for any of the three.
      it 'declares a Json column neither filterable nor sortable' do
        expect(collection.fields['team_ids'])
          .to have_attributes(column_type: 'Json', is_sortable: false, is_groupable: false, filter_operators: [])
      end

      # A filter the UI offers and the collection then answers by emptying the
      # page is the failure this whole datasource is built to avoid.
      it 'advertises only operators it can actually evaluate' do
        advertised = collection.fields.flat_map do |_name, column|
          column.filter_operators.map { |operator| [operator, column.column_type] }
        end

        expect(advertised.reject { |operator, type| evaluable?(operator, type) }).to be_empty
      end
    end

    describe '#list' do
      it 'reads every record of the endpoint and serializes it' do
        stub_admins(admin('1'), admin('2'))

        expect(ids(collection.list(nil, filter, nil))).to eq(%w[1 2])
      end

      it 'narrows the record to the projection' do
        stub_admins(admin('1'))

        expect(collection.list(nil, filter, %w[id email])).to eq([{ 'id' => '1', 'email' => '1@acme.test' }])
      end

      # Freshness over rate-limit thrift: nothing is kept from the previous list,
      # so an operator sees the teammates the workspace has now.
      it 'reads the endpoint again on the next list' do
        stub_admins(admin('1'))

        2.times { collection.list(nil, filter, nil) }

        expect(WebMock).to have_requested(:get, "#{base}/admins").twice
      end

      it 'propagates a failure rather than answering with no record' do
        stub_request(:get, "#{base}/admins").to_return(status: 500, body: '{}',
                                                       headers: { 'Content-Type' => 'application/json' })

        expect { collection.list(nil, filter, nil) }.to raise_error(APIError)
      end
    end

    describe '#list with a filter' do
      before { stub_admins(admin('1', 'name' => 'Alice'), admin('2', 'name' => 'Bob', 'has_inbox_seat' => false)) }

      def filtered(field, operator, value = nil)
        ids(collection.list(nil, filter(condition_tree: leaf(field, operator, value)), nil))
      end

      it 'keeps the rows a string condition names' do
        expect(filtered('name', operators::EQUAL, 'Alice')).to eq(%w[1])
      end

      it 'keeps the rows a boolean condition names' do
        expect(filtered('has_inbox_seat', operators::EQUAL, false)).to eq(%w[2])
      end

      it 'answers an operator it advertises through an equivalence' do
        expect(filtered('name', operators::I_CONTAINS, 'ali')).to eq(%w[1])
      end

      it 'answers nothing when nothing matches, rather than everything' do
        expect(filtered('name', operators::EQUAL, 'Nobody')).to be_empty
      end

      # `match` answers nil for an operator with no equivalence and `apply` reads
      # that as "no match", so this would otherwise be an empty page an operator
      # cannot tell from a real answer. The schema advertises no such operator; a
      # scope or a segment can still send one.
      it 'refuses a condition it cannot evaluate instead of emptying the page' do
        expect { filtered('team_ids', operators::EQUAL, 'x') }
          .to raise_error(UnsupportedOperatorError, /cannot filter 'team_ids' with 'equal'/)
      end

      it 'refuses a condition on a column it does not carry' do
        expect { filtered('unknown', operators::EQUAL, 'x') }
          .to raise_error(UnsupportedOperatorError, /cannot filter 'unknown'/)
      end

      it 'names a refusal after the operator, so the message says what to change' do
        expect { filtered('name', operators::LESS_THAN, 'x') }
          .to raise_error(UnsupportedOperatorError, /'less_than'/)
      end
    end

    describe '#list with a sort' do
      before do
        stub_admins(admin('2', 'name' => 'Bob'), admin('1', 'name' => 'Alice'), admin('3', 'name' => nil))
      end

      it 'orders on the column asked for' do
        expect(ids(collection.list(nil, filter(sort: sort({ field: 'name', ascending: true })), nil)))
          .to eq(%w[1 2 3])
      end

      # Nulls last ascending, first descending, the way a database orders them.
      it 'puts a null first on a descending order' do
        expect(ids(collection.list(nil, filter(sort: sort({ field: 'name', ascending: false })), nil)))
          .to eq(%w[3 2 1])
      end

      it 'keeps the order Intercom returned for rows the sort cannot separate' do
        rows = collection.list(nil, filter(sort: sort({ field: 'away_mode_enabled', ascending: true })), nil)

        expect(ids(rows)).to eq(%w[2 1 3])
      end

      it 'drops a clause naming a column it does not carry' do
        rows = collection.list(nil, filter(sort: sort({ field: 'unknown', ascending: true })), nil)

        expect(ids(rows)).to eq(%w[2 1 3])
      end
    end

    describe '#list with a page' do
      before { stub_admins(admin('1'), admin('2'), admin('3')) }

      it 'cuts the window out of the records in hand' do
        expect(ids(collection.list(nil, filter(page: page(1, 1)), nil))).to eq(%w[2])
      end

      it 'reads a page with no limit as every record past the offset' do
        expect(ids(collection.list(nil, filter(page: page(1, 0)), nil))).to eq(%w[2 3])
      end

      it 'answers an offset past the end with no record' do
        expect(collection.list(nil, filter(page: page(50, 10)), nil)).to be_empty
      end
    end

    describe '#aggregate' do
      before { stub_admins(admin('1', 'name' => 'Alice'), admin('2', 'name' => 'Bob', 'has_inbox_seat' => false)) }

      it 'counts every record, exactly' do
        expect(collection.aggregate(nil, filter, aggregation('Count')))
          .to eq([{ 'group' => {}, 'value' => 2 }])
      end

      it 'counts the rows a filter keeps' do
        filtered = filter(condition_tree: leaf('has_inbox_seat', operators::EQUAL, true))

        expect(collection.aggregate(nil, filtered, aggregation('Count')).first['value']).to eq(1)
      end

      it 'groups on a column, which is exact for the same reason' do
        rows = collection.aggregate(nil, filter, aggregation('Count', groups: [{ field: 'has_inbox_seat' }]))

        expect(rows.sum { |row| row['value'] }).to eq(2)
        expect(rows.size).to eq(2)
      end
    end

    describe 'the hooks a collection has to implement' do
      let(:incomplete) do
        Class.new(described_class) do
          def initialize(datasource)
            super(datasource, 'Incomplete')
          end

          def define_schema
            add_column('id', 'String', is_primary_key: true)
          end
        end
      end

      it 'says which one is missing rather than failing obscurely' do
        expect { incomplete.new(datasource).list(nil, filter, nil) }
          .to raise_error(NotImplementedError, /did not implement fetch_all/)
      end
    end
  end
end
