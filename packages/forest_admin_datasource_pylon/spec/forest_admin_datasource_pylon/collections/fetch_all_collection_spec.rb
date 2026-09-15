module ForestAdminDatasourcePylon
  RSpec.describe Collections::FetchAllCollection do
    def leaf(field, operator, value = nil)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
        .new(field, operator, value)
    end

    def filter(condition_tree: nil, page: nil, sort: nil)
      ForestAdminDatasourceToolkit::Components::Query::Filter.new(
        condition_tree: condition_tree, page: page, sort: sort
      )
    end

    def page(offset, limit)
      ForestAdminDatasourceToolkit::Components::Query::Page.new(offset: offset, limit: limit)
    end

    def aggregation(operation, field: nil, groups: [])
      ForestAdminDatasourceToolkit::Components::Query::Aggregation.new(
        operation: operation, field: field, groups: groups
      )
    end

    def sort(*clauses)
      ForestAdminDatasourceToolkit::Components::Query::Sort.new(clauses)
    end

    def by(field, ascending: true)
      { field: field, ascending: ascending }
    end

    def ids(records)
      records.map { |record| record['id'] }
    end

    # Mirrors `residual_leaf_appliable?`: an operator is evaluable in memory when
    # `ConditionTreeLeaf#match` handles it natively or the toolkit can rewrite it
    # into operators that it does.
    def appliable?(operator, column_type)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::ConditionTreeEquivalent
        .equivalent_tree?(operator, Collections::BaseCollection::IN_MEMORY_OPERATORS, column_type)
    end

    def advertised(collection)
      collection.fields.flat_map do |name, column|
        column.filter_operators.map { |operator| [name, operator, column.column_type] }
      end
    end

    # A filter value of the shape the operator expects, so every advertised
    # operator can be run for real over the dataset.
    def value_for(operator, column_type)
      return nil if [operators::PRESENT, operators::BLANK].include?(operator)

      sample = column_type == 'Boolean' ? true : 'Bob'
      [operators::IN, operators::NOT_IN].include?(operator) ? [sample] : sample
    end

    let(:operators) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators }
    let(:datasource) { instance_double(ForestAdminDatasourcePylon::Datasource) }

    # A collection over an in-memory dataset: the endpoint hook hands back what
    # the example set, so the shared flow can be observed without the HTTP layer.
    let(:subclass) do
      Class.new(described_class) do
        attr_accessor :entities

        def define_schema
          add_column('id', 'String', is_primary_key: true)
          add_column('name', 'String')
          add_column('flag', 'Boolean')
          add_column('resolved_at', 'Date')
          add_column('list', 'Json')
        end

        def define_relations; end

        protected

        def fetch_all
          @entities
        end

        def serialize(entity)
          entity
        end
      end
    end

    # Deliberately out of order, with a record whose every value is null: the
    # API imposes no order, and Pylon spells an unset value as null.
    let(:entities) do
      [{ 'id' => 'u2', 'name' => 'Bob', 'flag' => false, 'resolved_at' => nil, 'list' => %w[a] },
       { 'id' => 'u1', 'name' => 'alice', 'flag' => true, 'resolved_at' => '2026-01-02T00:00:00Z', 'list' => [] },
       { 'id' => 'u3', 'name' => nil, 'flag' => nil, 'resolved_at' => nil, 'list' => nil }]
    end

    let(:collection) { subclass.new(datasource, 'X').tap { |instance| instance.entities = entities } }

    describe 'subclass contract' do
      let(:schema_only) do
        Class.new(described_class) do
          def define_schema; end
          def define_relations; end
        end
      end

      it 'names fetch_all when the endpoint hook is missing' do
        expect { schema_only.new(datasource, 'X').list(nil, nil, nil) }
          .to raise_error(NotImplementedError, /did not implement fetch_all/)
      end

      it 'names serialize when the serialization hook is missing' do
        fetching = Class.new(schema_only) do
          protected

          def fetch_all
            [{ 'id' => 'u1' }]
          end
        end

        expect { fetching.new(datasource, 'X').list(nil, nil, nil) }
          .to raise_error(NotImplementedError, /did not implement serialize/)
      end

      # Neither endpoint carries a search parameter. Count is the one capability
      # a collection holding the whole dataset can answer exactly, where every
      # cursor-backed one would be counting the pages it happened to walk.
      it 'leaves search disabled and enables count' do
        expect(collection.is_searchable?).to be(false)
        expect(collection.is_countable?).to be(true)
      end

      # A group is computed over the complete dataset here, unlike every other
      # Pylon collection: a chart grouped by a scalar column is exact.
      it 'declares the scalar columns groupable and the json one not' do
        expect(collection.fields['name'].is_groupable).to be(true)
        expect(collection.fields['list'].is_groupable).to be(false)
      end

      # Pylon defines custom fields on issues, accounts and contacts only, and
      # nothing here reads a custom-field value nor clamps its operators: the
      # column would read nil on every row forever.
      it 'refuses a custom field rather than registering a column nothing fills' do
        declared = { column_name: 'tier',
                     schema: ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(column_type: 'String') }

        expect { subclass.new(datasource, 'X', custom_fields: [declared]) }
          .to raise_error(ConfigurationError, /takes no custom field/)
      end
    end

    # How a collection pointing here with a ManyToOne resolves its foreign keys.
    # The endpoint hands back the complete dataset, so the ids only pick rows out
    # of it and any number of them costs the same single read.
    describe '#records_indexed_by_id' do
      it 'indexes the wanted records by id' do
        expect(collection.records_indexed_by_id(%w[u3 u1]))
          .to eq('u1' => entities[1], 'u3' => entities[2])
      end

      it 'leaves out an id the endpoint no longer returns rather than indexing a blank record' do
        expect(collection.records_indexed_by_id(%w[u1 gone]).keys).to eq(%w[u1])
      end

      # A page of the pointing collection asks for a handful of ids against every
      # record the organization has: serializing the whole dataset to slice it
      # afterwards would pay for all of them, on every page.
      it 'serializes the wanted records only' do
        counting = Class.new(subclass) do
          attr_reader :serialized

          protected

          def serialize(entity)
            (@serialized ||= []) << entity['id']
            entity
          end
        end.new(datasource, 'X')
        counting.entities = entities

        counting.records_indexed_by_id(%w[u1])

        expect(counting.serialized).to eq(%w[u1])
      end
    end

    # Exact where every other Pylon collection has to refuse: the records in
    # hand are every record Pylon holds, so a count over them is the count a
    # server-side aggregation would have answered.
    describe '#aggregate' do
      it 'counts the records the filter keeps' do
        expect(collection.aggregate(nil, filter, aggregation('Count')))
          .to eq([{ 'group' => {}, 'value' => 3 }])
        expect(collection.aggregate(nil, filter(condition_tree: leaf('name', operators::PRESENT)),
                                    aggregation('Count')))
          .to eq([{ 'group' => {}, 'value' => 2 }])
      end

      it 'groups by a column' do
        rows = collection.aggregate(nil, filter, aggregation('Count', groups: [{ field: 'flag' }]))

        expect(rows).to contain_exactly({ 'group' => { 'flag' => false }, 'value' => 1 },
                                        { 'group' => { 'flag' => true }, 'value' => 1 },
                                        { 'group' => { 'flag' => nil }, 'value' => 1 })
      end

      it 'honours the limit the chart asks for' do
        rows = collection.aggregate(nil, filter, aggregation('Count', groups: [{ field: 'name' }]), 1)

        expect(rows.size).to eq(1)
      end
    end

    describe '.operators_for' do
      it 'advertises the string filters the in-memory pass can evaluate' do
        expect(described_class.operators_for('String'))
          .to eq([operators::EQUAL, operators::NOT_EQUAL, operators::IN, operators::NOT_IN,
                  operators::PRESENT, operators::BLANK, operators::CONTAINS, operators::I_CONTAINS,
                  operators::NOT_CONTAINS, operators::STARTS_WITH, operators::ENDS_WITH])
      end

      it 'advertises the boolean filters the in-memory pass can evaluate' do
        expect(described_class.operators_for('Boolean'))
          .to eq([operators::EQUAL, operators::NOT_EQUAL, operators::IN, operators::NOT_IN,
                  operators::PRESENT, operators::BLANK])
      end

      # A Json column holds a list whose Pylon semantics have no in-memory
      # counterpart, and a type with no candidate is not guessed at: both
      # advertise nothing rather than a filter that could answer wrongly.
      it 'advertises no filter on a json column nor on a type it has no candidate for' do
        expect(described_class.operators_for('Json')).to eq([])
        expect(described_class.operators_for('Date')).to eq([])
      end

      # The schema is the contract the UI builds its filters from: an operator
      # in it that memory cannot evaluate would silently empty the page.
      it 'advertises only operators the in-memory pass can evaluate' do
        unappliable = advertised(collection).reject { |_field, operator, type| appliable?(operator, type) }

        expect(unappliable).to be_empty
      end

      it 'evaluates every advertised operator over the dataset, nulls included' do
        failures = advertised(collection).filter_map do |field, operator, type|
          collection.list(nil, filter(condition_tree: leaf(field, operator, value_for(operator, type))), nil)
          nil
        rescue StandardError => e
          "#{field} #{operator}: #{e.class}: #{e.message}"
        end

        expect(failures).to be_empty
      end
    end

    describe '#list' do
      it 'serializes every record the endpoint returned when nothing is filtered' do
        expect(ids(collection.list(nil, filter, nil))).to eq(%w[u2 u1 u3])
        expect(collection.list(nil, nil, nil).size).to eq(3)
      end

      it 'restricts the records to the projection' do
        expect(collection.list(nil, filter(sort: sort(by('id'))), %w[id name]))
          .to eq([{ 'id' => 'u1', 'name' => 'alice' }, { 'id' => 'u2', 'name' => 'Bob' },
                  { 'id' => 'u3', 'name' => nil }])
      end

      # Cut out of the complete, ordered dataset, so the window holds the rows a
      # server-side query would have returned for it.
      it 'slices the requested page out of the ordered records' do
        expect(ids(collection.list(nil, filter(sort: sort(by('id')), page: page(1, 1)), nil))).to eq(%w[u2])
      end

      # A read asking for no page asks for the whole dataset, which is the read
      # `SortCollectionDecorator` performs to build its reference order: capping
      # it at the search limit would drop every record past the thousandth and
      # leave the decorator without a position for them.
      it 'answers a page-less read with every record, past the search limit' do
        collection.entities = Array.new(Client::MAX_SEARCH_LIMIT + 5) { |i| { 'id' => "u#{i}" } }

        expect(collection.list(nil, filter, nil).size).to eq(Client::MAX_SEARCH_LIMIT + 5)
        expect(collection.list(nil, nil, nil).size).to eq(Client::MAX_SEARCH_LIMIT + 5)
      end

      # The same read with an offset and no limit -- which `Page#apply` reads as
      # "to the end of the records" too: the offset is honoured, the tail is not
      # cut.
      it 'honours an offset carrying no limit without capping the tail' do
        collection.entities = Array.new(Client::MAX_SEARCH_LIMIT + 5) { |i| { 'id' => "u#{i}" } }
        query = filter(page: page(2, nil))

        expect(collection.list(nil, query, nil).size).to eq(Client::MAX_SEARCH_LIMIT + 3)
      end
    end

    describe '#list with a filter' do
      def filtered(field, operator, value = nil)
        ids(collection.list(nil, filter(condition_tree: leaf(field, operator, value)), nil))
      end

      it 'keeps the records the condition tree matches, in the order the API returned them' do
        expect(filtered('id', operators::IN, %w[u1 u2])).to eq(%w[u2 u1])
        expect(filtered('name', operators::CONTAINS, 'li')).to eq(%w[u1])
        expect(filtered('flag', operators::EQUAL, true)).to eq(%w[u1])
      end

      # The default search the agent builds for a non-searchable collection is a
      # case-insensitive contains, which is why the operator is advertised.
      it 'matches a contains regardless of case through i_contains' do
        expect(filtered('name', operators::I_CONTAINS, 'ALI')).to eq(%w[u1])
        expect(filtered('name', operators::CONTAINS, 'ALI')).to eq([])
      end

      it 'reads a null column as blank rather than as a value' do
        expect(filtered('name', operators::BLANK)).to eq(%w[u3])
        expect(filtered('name', operators::PRESENT)).to eq(%w[u2 u1])
        expect(filtered('flag', operators::BLANK)).to eq(%w[u3])
      end

      # `ConditionTreeLeaf#match` compares with a bare `>`, which raises on the
      # null Pylon returns for an unset column. Nothing in the schema advertises
      # the comparison, but a scope or a customizer can still send one.
      it 'excludes a null column from a comparison instead of raising' do
        expect(filtered('resolved_at', operators::GREATER_THAN, '2026-01-01T00:00:00Z')).to eq(%w[u1])
      end
    end

    describe '#list with a sort' do
      def sorted(*clauses)
        ids(collection.list(nil, filter(sort: sort(*clauses)), nil))
      end

      it 'honours an ascending and a descending order' do
        expect(sorted(by('name'))).to eq(%w[u2 u1 u3])
        expect(sorted(by('name', ascending: false))).to eq(%w[u3 u1 u2])
      end

      # The agent injects this exact order whenever the request asks for none,
      # and unlike the endpoints Pylon orders itself, it is honoured here.
      it 'honours the ascending primary-key sort the agent injects' do
        expect(sorted(by('id'))).to eq(%w[u1 u2 u3])
      end

      # `false <=> true` is nil in Ruby: the order would be arbitrary without a
      # comparator of its own.
      it 'orders a boolean column, false first, the way a database does' do
        expect(sorted(by('flag'))).to eq(%w[u2 u1 u3])
        expect(sorted(by('flag', ascending: false))).to eq(%w[u3 u1 u2])
      end

      it 'moves on to the next clause for the records the first cannot tell apart' do
        collection.entities = [{ 'id' => 'u2', 'flag' => true, 'name' => 'Bob' },
                               { 'id' => 'u1', 'flag' => true, 'name' => 'alice' },
                               { 'id' => 'u3', 'flag' => false, 'name' => 'Zoe' }]

        expect(sorted(by('flag'), by('name'))).to eq(%w[u3 u2 u1])
      end

      # Ruby's `sort` is not stable, so the position the API returned the record
      # in breaks the ties: the same request cannot answer in a different order.
      it 'keeps the order the API returned for records the sort cannot tell apart' do
        collection.entities = [{ 'id' => 'u3', 'name' => 'same' }, { 'id' => 'u1', 'name' => 'same' },
                               { 'id' => 'u2', 'name' => 'same' }]

        expect(sorted(by('name'))).to eq(%w[u3 u1 u2])
      end

      it 'keeps two null columns in place rather than comparing them' do
        collection.entities = [{ 'id' => 'u2', 'name' => nil }, { 'id' => 'u1', 'name' => nil }]

        expect(sorted(by('name'))).to eq(%w[u2 u1])
      end
    end
  end
end
