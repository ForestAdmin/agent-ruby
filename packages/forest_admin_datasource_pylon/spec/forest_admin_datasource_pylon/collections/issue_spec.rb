module ForestAdminDatasourcePylon
  RSpec.describe Collections::Issue do
    def filter(condition_tree: nil, search: nil, page: nil, sort: nil)
      ForestAdminDatasourceToolkit::Components::Query::Filter.new(
        condition_tree: condition_tree, search: search, page: page, sort: sort
      )
    end

    def leaf(field, operator, value)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
        .new(field, operator, value)
    end

    def branch(aggregator, conditions)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch
        .new(aggregator, conditions)
    end

    def id_leaf(operator, value)
      leaf('id', operator, value)
    end

    def page(offset, limit)
      ForestAdminDatasourceToolkit::Components::Query::Page.new(offset: offset, limit: limit)
    end

    def json(payload, status = 200)
      { status: status, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end

    # Trimmed to the shape observed on the API: parties are nested objects
    # carrying an id, and unset values come back as null rather than absent.
    def issue_payload(id, overrides = {})
      {
        'id' => id, 'number' => 12, 'title' => 'Boom', 'link' => "https://app.usepylon.com/issues?issueNumber=#{id}",
        'body_html' => '<p>boom</p>', 'state' => 'new', 'type' => 'ticket', 'source' => 'manual',
        'account' => { 'id' => 'acc-1', 'external_ids' => nil }, 'requester' => { 'id' => 'req-1' },
        'assignee' => nil, 'team' => nil, 'tags' => %w[urgent], 'custom_fields' => {},
        'first_response_time' => nil, 'resolution_time' => nil, 'latest_message_time' => '2026-08-07T13:06:22Z',
        'created_at' => '2026-08-07T13:06:22Z', 'updated_at' => '2026-08-07T13:06:22Z',
        'customer_portal_visible' => false, 'number_of_touches' => 0, 'author_unverified' => false,
        'time_in_status_seconds' => { 'open' => 701_211 },
        'business_hours_time_in_status_seconds' => { 'open' => 172_799 }
      }.merge(overrides)
    end

    # Relations are fields too; the assertions on the columns select them out.
    def columns
      collection.fields.select { |_name, field| field.type == 'Column' }
    end

    let(:datasource) { ForestAdminDatasourcePylon::Datasource.new(api_key: 'k') }
    let(:collection) { datasource.get_collection('PylonIssue') }
    let(:base) { datasource.configuration.url }
    let(:operators) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators }

    before { stub_custom_fields }

    describe 'schema' do
      it 'is named PylonIssue' do
        expect(collection.name).to eq('PylonIssue')
      end

      it 'declares id as the primary key' do
        expect(collection.fields['id'].is_primary_key).to be(true)
      end

      it 'only advertises the id operators the short-circuit can serve' do
        expect(collection.fields['id'].filter_operators).to eq([operators::EQUAL, operators::IN])
      end

      it 'exposes the native columns observed on the API' do
        expect(collection.fields.keys).to include(
          'number', 'title', 'body_html', 'state', 'type', 'source', 'link', 'tags',
          'account_id', 'requester_id', 'assignee_id', 'team_id',
          'first_response_time', 'resolution_time', 'latest_message_time', 'created_at', 'updated_at',
          'customer_portal_visible', 'author_unverified', 'number_of_touches',
          'time_in_status_seconds', 'business_hours_time_in_status_seconds'
        )
      end

      it 'types the response-time columns as dates, not durations' do
        expect(collection.fields['first_response_time'].column_type).to eq('Date')
        expect(collection.fields['resolution_time'].column_type).to eq('Date')
      end

      # /issues/search exposes no sort parameter.
      it 'declares every column non-sortable' do
        expect(columns.values.map(&:is_sortable).uniq).to eq([false])
      end

      # Writable is what POST /issues or PATCH /issues/{id} accepts; everything
      # Pylon computes itself stays read-only.
      it 'declares writable exactly the columns an endpoint takes' do
        writable = columns.reject { |_name, column| column.is_read_only }.keys

        expect(writable).to contain_exactly('title', 'body_html', 'state', 'type', 'tags',
                                            'customer_portal_visible', 'author_unverified',
                                            'account_id', 'requester_id', 'assignee_id', 'team_id')
      end

      # No Pylon endpoint aggregates, and the pages of a cursor walk are not the
      # dataset: a chart grouped by one of these columns would answer a fraction
      # as if it were the whole collection.
      it 'declares no column groupable' do
        expect(columns.values.map(&:is_groupable).uniq).to eq([false])
      end

      # `search_text` is native on /issues/search, while Pylon exposes neither a
      # count endpoint nor a total, so Count stays out until it can be throttled.
      it 'enables search and leaves count disabled' do
        expect(collection.is_searchable?).to be(true)
        expect(collection.is_countable?).to be(false)
      end

      it 'advertises only the operators the search allow-list accepts' do
        expect(collection.fields['state'].filter_operators).to eq([operators::EQUAL, operators::IN,
                                                                   operators::NOT_IN])
        expect(collection.fields['assignee_id'].filter_operators)
          .to eq([operators::EQUAL, operators::IN, operators::NOT_IN,
                  operators::PRESENT, operators::BLANK, operators::MISSING])
        expect(collection.fields['title'].filter_operators)
          .to eq([operators::CONTAINS, operators::I_CONTAINS, operators::NOT_CONTAINS, operators::NOT_I_CONTAINS])
      end

      # Declaring the bare comparisons is what lets the toolkit rewrite Today /
      # PreviousWeek / ... into a pair of bounds Pylon understands.
      it 'advertises the date columns with the two bounds Pylon accepts' do
        expect(collection.fields['created_at'].filter_operators)
          .to eq([operators::GREATER_THAN, operators::LESS_THAN])
      end

      # /issues/search cannot filter on them, so offering the filter would only
      # produce an error once the operator used it.
      it 'advertises no operator on the columns Pylon cannot filter' do
        %w[number source number_of_touches first_response_time link
           customer_portal_visible time_in_status_seconds].each do |field|
          expect(collection.fields[field].filter_operators).to eq([])
        end
      end
    end

    describe 'relations' do
      let(:many_to_one) { ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema }

      it 'declares a ManyToOne for each of the four parties of an issue' do
        expect(collection.fields.values_at('account', 'requester', 'assignee', 'team'))
          .to all(be_a(many_to_one))
      end

      it 'points each one at the collection owning its shape, through the flattened foreign key' do
        expect(collection.fields['account'])
          .to have_attributes(foreign_collection: 'PylonAccount', foreign_key: 'account_id',
                              foreign_key_target: 'id')
        expect(collection.fields['requester'])
          .to have_attributes(foreign_collection: 'PylonContact', foreign_key: 'requester_id',
                              foreign_key_target: 'id')
        expect(collection.fields['assignee'])
          .to have_attributes(foreign_collection: 'PylonUser', foreign_key: 'assignee_id',
                              foreign_key_target: 'id')
        expect(collection.fields['team'])
          .to have_attributes(foreign_collection: 'PylonTeam', foreign_key: 'team_id',
                              foreign_key_target: 'id')
      end

      # The key is what `/issues/search` filters, on this side and on the reverse
      # one, so it stays a column of its own next to the relation.
      it 'keeps the foreign keys as columns' do
        expect(columns.keys).to include('account_id', 'requester_id', 'assignee_id', 'team_id')
      end
    end

    describe '#list' do
      it 'searches for the most recent issues and serializes them' do
        stub_request(:post, "#{base}/issues/search").to_return(json('data' => [issue_payload('i1')]))

        rows = collection.list(nil, filter, nil)

        expect(rows.size).to eq(1)
        expect(rows.first).to include('id' => 'i1', 'title' => 'Boom', 'state' => 'new',
                                      'tags' => ['urgent'], 'number_of_touches' => 0)
      end

      it 'flattens the nested parties into foreign-key columns' do
        stub_request(:post, "#{base}/issues/search").to_return(json('data' => [issue_payload('i1')]))

        expect(collection.list(nil, filter, nil).first)
          .to include('account_id' => 'acc-1', 'requester_id' => 'req-1',
                      'assignee_id' => nil, 'team_id' => nil)
      end

      it 'keeps the nested objects out of the serialized record' do
        stub_request(:post, "#{base}/issues/search").to_return(json('data' => [issue_payload('i1')]))

        expect(collection.list(nil, filter, nil).first.keys)
          .not_to include('account', 'requester', 'assignee', 'team')
      end

      it 'restricts the record to the projection' do
        stub_request(:post, "#{base}/issues/search").to_return(json('data' => [issue_payload('i1')]))

        expect(collection.list(nil, filter, %w[id title])).to eq([{ 'id' => 'i1', 'title' => 'Boom' }])
      end

      it 'forwards the requested page as the search limit' do
        stub_request(:post, "#{base}/issues/search").to_return(json('data' => [issue_payload('i1')]))

        collection.list(nil, filter(page: page(0, 1)), nil)

        expect(WebMock).to have_requested(:post, "#{base}/issues/search").with(body: { 'limit' => 1 })
      end

      it 'returns an empty list when the search returns nothing' do
        stub_request(:post, "#{base}/issues/search").to_return(json('data' => []))

        expect(collection.list(nil, filter, nil)).to eq([])
      end
    end

    describe '#list across cursor pages' do
      it 'walks the cursor until the requested window is covered' do
        stub_request(:post, "#{base}/issues/search")
          .with(body: { 'limit' => 3 })
          .to_return(json('data' => [issue_payload('i1'), issue_payload('i2')],
                          'pagination' => { 'cursor' => 'c1', 'has_next_page' => true }))
        stub_request(:post, "#{base}/issues/search")
          .with(body: { 'limit' => 1, 'cursor' => 'c1' })
          .to_return(json('data' => [issue_payload('i3')]))

        rows = collection.list(nil, filter(page: page(2, 1)), %w[id])

        expect(rows).to eq([{ 'id' => 'i3' }])
      end

      it 'stops on the last page even when the window is not filled' do
        stub_request(:post, "#{base}/issues/search").to_return(json('data' => [issue_payload('i1')]))

        rows = collection.list(nil, filter(page: page(0, 50)), %w[id])

        expect(rows).to eq([{ 'id' => 'i1' }])
        expect(WebMock).to have_requested(:post, "#{base}/issues/search").once
      end
    end

    describe '#list on a primary-key lookup' do
      it 'reads the issue directly instead of searching' do
        stub_request(:get, "#{base}/issues/i1").to_return(json('data' => issue_payload('i1')))

        rows = collection.list(nil, filter(condition_tree: id_leaf(operators::EQUAL, 'i1')), %w[id title])

        expect(rows).to eq([{ 'id' => 'i1', 'title' => 'Boom' }])
        expect(WebMock).not_to have_requested(:post, "#{base}/issues/search")
      end

      it 'reads every id of an in filter, preserving their order' do
        stub_request(:get, "#{base}/issues/i1").to_return(json('data' => issue_payload('i1')))
        stub_request(:get, "#{base}/issues/i2").to_return(json('data' => issue_payload('i2')))

        rows = collection.list(nil, filter(condition_tree: id_leaf(operators::IN, %w[i1 i2])), %w[id])

        expect(rows).to eq([{ 'id' => 'i1' }, { 'id' => 'i2' }])
      end

      it 'applies the requested page to an in lookup' do
        %w[i1 i2 i3].each do |id|
          stub_request(:get, "#{base}/issues/#{id}").to_return(json('data' => issue_payload(id)))
        end
        query = filter(condition_tree: id_leaf(operators::IN, %w[i1 i2 i3]), page: page(1, 1))

        expect(collection.list(nil, query, %w[id])).to eq([{ 'id' => 'i2' }])
      end

      # The window is taken off the ids, so it is the ids of the page that are
      # read and no others: one that no longer resolves leaves a gap rather
      # than pulling the next id in behind it, which would cost a request per
      # record outside the page to find out.
      it 'reads only the ids of the page, gap included, when one no longer exists' do
        stub_request(:get, "#{base}/issues/gone").to_return(json({ 'message' => 'not found' }, 404))
        %w[i2 i3].each do |id|
          stub_request(:get, "#{base}/issues/#{id}").to_return(json('data' => issue_payload(id)))
        end
        query = filter(condition_tree: id_leaf(operators::IN, %w[gone i2 i3]), page: page(0, 2))

        expect(collection.list(nil, query, %w[id])).to eq([{ 'id' => 'i2' }])
        expect(WebMock).not_to have_requested(:get, "#{base}/issues/i3")
      end

      # The cap bounds a page, not a selection: an offset past it used to read
      # the first MAX_ID_LOOKUPS ids and answer an empty page from them.
      it 'answers a page past the lookup cap instead of an empty one' do
        ids = Array.new(30) { |i| "i#{i + 1}" }
        %w[i21 i22].each do |id|
          stub_request(:get, "#{base}/issues/#{id}").to_return(json('data' => issue_payload(id)))
        end
        query = filter(condition_tree: id_leaf(operators::IN, ids), page: page(20, 2))

        expect(collection.list(nil, query, %w[id])).to eq([{ 'id' => 'i21' }, { 'id' => 'i22' }])
        expect(WebMock).not_to have_requested(:get, "#{base}/issues/i1")
      end

      # An `and` names the records all of its conditions name, so two `id`
      # leaves intersect: keeping only the first would apply the cap to the
      # wider set and refuse a selection narrower than it.
      it 'intersects two id conditions of an and rather than refusing over the wider one' do
        wide = Array.new(Collections::Issue::MAX_ID_LOOKUPS + 5) { |i| "i#{i}" }
        %w[i2 i4].each do |id|
          stub_request(:get, "#{base}/issues/#{id}").to_return(json('data' => issue_payload(id)))
        end
        tree = branch('And', [id_leaf(operators::IN, wide), id_leaf(operators::IN, %w[i2 i4])])

        expect(collection.list(nil, filter(condition_tree: tree), %w[id]))
          .to eq([{ 'id' => 'i2' }, { 'id' => 'i4' }])
        expect(WebMock).not_to have_requested(:get, "#{base}/issues/i0")
      end

      it 'reads nothing when the two id conditions of an and are disjoint' do
        tree = branch('And', [id_leaf(operators::IN, %w[i1 i2]), id_leaf(operators::EQUAL, 'i9')])

        expect(collection.list(nil, filter(condition_tree: tree), %w[id])).to eq([])
        expect(WebMock).not_to have_requested(:get, "#{base}/issues/i1")
      end

      # Which records the window holds is only known once they are all read, so
      # a wide selection carrying other conditions cannot be answered a page at
      # a time, and is refused rather than answered with a fraction of itself.
      it 'refuses a selection past the cap that filters the named issues further' do
        ids = Array.new(Collections::Issue::MAX_ID_LOOKUPS + 5) { |i| "i#{i}" }
        tree = branch('And', [id_leaf(operators::IN, ids), leaf('state', operators::EQUAL, 'new')])

        expect { collection.list(nil, filter(condition_tree: tree), %w[id]) }
          .to raise_error(UnsupportedOperatorError, /names #{ids.size} issues by id/)
      end

      it 'skips an issue that no longer exists' do
        stub_request(:get, "#{base}/issues/i1").to_return(json('data' => issue_payload('i1')))
        stub_request(:get, "#{base}/issues/gone").to_return(json({ 'message' => 'not found' }, 404))

        rows = collection.list(nil, filter(condition_tree: id_leaf(operators::IN, %w[i1 gone])), %w[id])

        expect(rows).to eq([{ 'id' => 'i1' }])
      end

      it 'propagates a failure that is not a missing record' do
        stub_request(:get, "#{base}/issues/i1").to_return(json({ 'message' => 'boom' }, 500))

        expect { collection.list(nil, filter(condition_tree: id_leaf(operators::EQUAL, 'i1')), %w[id]) }
          .to raise_error(APIError)
      end

      # `GET /issues/{id}` accepts the issue number as well as the UUID and
      # answers with the issue carrying its own id: keeping it would answer
      # `id equals 42` with a row whose id is not 42.
      it 'reports no record when the endpoint answered an alias of the primary key' do
        stub_request(:get, "#{base}/issues/42").to_return(json('data' => issue_payload('i1')))

        expect(collection.list(nil, filter(condition_tree: id_leaf(operators::EQUAL, '42')), %w[id])).to eq([])
      end
    end

    describe 'custom fields' do
      let(:column) do
        ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(column_type: 'String',
                                                               filter_operators: [operators::EQUAL])
      end
      let(:collection) do
        described_class.new(datasource, custom_fields: [{ column_name: 'severity', schema: column },
                                                        { column_name: 'zones', schema: column }])
      end

      it 'serializes single- and multi-value custom fields' do
        fields = { 'severity' => { 'slug' => 'severity', 'value' => 'high' },
                   'zones' => { 'slug' => 'zones', 'values' => %w[eu us] } }
        stub_request(:post, "#{base}/issues/search")
          .to_return(json('data' => [issue_payload('i1', 'custom_fields' => fields)]))

        expect(collection.list(nil, filter, nil).first).to include('severity' => 'high', 'zones' => %w[eu us])
      end

      it 'yields nil for a custom field the issue does not carry' do
        stub_request(:post, "#{base}/issues/search").to_return(json('data' => [issue_payload('i1')]))

        expect(collection.list(nil, filter, nil).first).to include('severity' => nil, 'zones' => nil)
      end

      # Pylon accepts a custom-field slug as a filter field, with the operators
      # the integrator declared on the column.
      it 'filters a custom field through its slug' do
        stub_request(:post, "#{base}/issues/search").to_return(json('data' => []))

        collection.list(nil, filter(condition_tree: leaf('severity', operators::EQUAL, 'high')), %w[id])

        expect(WebMock).to have_requested(:post, "#{base}/issues/search")
          .with(body: hash_including('filter' => { 'field' => 'severity', 'operator' => 'equals',
                                                   'value' => 'high' }))
      end

      it 'refuses an operator the custom field does not declare' do
        expect { collection.list(nil, filter(condition_tree: leaf('severity', operators::CONTAINS, 'hi')), %w[id]) }
          .to raise_error(UnsupportedOperatorError, /not supported on field 'severity'/)
      end

      # Clamped at registration, so the schema never advertises an operator
      # the translator would refuse at query time.
      it 'drops a declared operator Pylon cannot honour on a custom field and warns' do
        allow(ForestAdminDatasourcePylon.logger).to receive(:warn)
        declared = ForestAdminDatasourceToolkit::Schema::ColumnSchema
                   .new(column_type: 'String', filter_operators: [operators::EQUAL, operators::STARTS_WITH])

        clamped = described_class.new(datasource, custom_fields: [{ column_name: 'severity', schema: declared }])

        expect(clamped.fields['severity'].filter_operators).to eq([operators::EQUAL])
        expect(ForestAdminDatasourcePylon.logger)
          .to have_received(:warn).with(/cannot honour on a custom field \(starts_with\)/)
      end

      # The API reference documents what a custom field is, never the form its
      # value is read back in. The column holds the form the agent gives a filter
      # value of the same type, so the two stay comparable whichever one Pylon
      # answered with.
      describe 'the form a value is read in' do
        def typed(type)
          ForestAdminDatasourceToolkit::Schema::ColumnSchema
            .new(column_type: type, filter_operators: [operators::EQUAL])
        end

        def entry(slug, value)
          { slug => { 'slug' => slug, 'value' => value } }
        end

        def read(fields)
          stub_request(:post, "#{base}/issues/search")
            .to_return(json('data' => [issue_payload('i1', 'custom_fields' => fields)]))

          collection.list(nil, filter, nil).first
        end

        let(:collection) do
          described_class.new(datasource, custom_fields: [{ column_name: 'nps', schema: typed('Number') },
                                                          { column_name: 'vip', schema: typed('Boolean') },
                                                          { column_name: 'renewal', schema: typed('Dateonly') }])
        end

        # A value already numeric keeps its own form: widening `42` into `42.0`
        # would display a decimal the field does not hold, where the wire half
        # narrows the same value back. A string is read to the tightest form, so
        # both halves agree on what an integer looks like.
        [[42, 42], ['42', 42], [' 42 ', 42], [42.0, 42.0], [42.5, 42.5], ['42.5', 42.5],
         ['42.0', 42]].each do |raw, expected|
          it "reads a number answered as #{raw.inspect} as #{expected.inspect}" do
            expect(read(entry('nps', raw))['nps']).to eql(expected)
          end
        end

        it 'reads a number it cannot make sense of as absent rather than as zero' do
          expect(read(entry('nps', 'n/a'))['nps']).to be_nil
        end

        [[true, true], ['true', true], [false, false], ['false', false], ['0', false]].each do |raw, expected|
          it "reads a boolean answered as #{raw.inspect} as #{expected}" do
            expect(read(entry('vip', raw))['vip']).to be(expected)
          end
        end

        it 'reads an empty boolean as absent, false being an answer of its own' do
          expect(read(entry('vip', ''))['vip']).to be_nil
        end

        it 'leaves a date the ISO string the filter is compared with' do
          expect(read(entry('renewal', '2026-08-01'))['renewal']).to eq('2026-08-01')
        end

        it 'leaves a field the issue does not carry absent' do
          expect(read({})).to include('nps' => nil, 'vip' => nil, 'renewal' => nil)
        end

        # The one place the form decides the result: an id filter is answered by
        # `GET /issues/{id}` and the rest is applied in memory, so a number left
        # as `"42"` would be compared with the `42.0` the agent casts the filter
        # to, and the row would be dropped without a word. Reading it as the
        # Integer `42` is enough -- `match` compares with `==`.
        it 'keeps a row matched on a number combined with an id lookup' do
          stub_request(:get, "#{base}/issues/i1")
            .to_return(json('data' => issue_payload('i1', 'custom_fields' => entry('nps', '42'))))
          tree = branch('And', [id_leaf(operators::EQUAL, 'i1'), leaf('nps', operators::EQUAL, 42.0)])

          expect(collection.list(nil, filter(condition_tree: tree), %w[id nps]))
            .to eq([{ 'id' => 'i1', 'nps' => 42 }])
        end

        # The same row, matched through a membership filter: `Array#include?`
        # compares with `==` too, so the Integer read answers the float list.
        it 'keeps a row matched on a number list combined with an id lookup' do
          stub_request(:get, "#{base}/issues/i1")
            .to_return(json('data' => issue_payload('i1', 'custom_fields' => entry('nps', '42'))))
          tree = branch('And', [id_leaf(operators::EQUAL, 'i1'), leaf('nps', operators::IN, [42.0, 7.0])])

          expect(collection.list(nil, filter(condition_tree: tree), %w[id nps]))
            .to eq([{ 'id' => 'i1', 'nps' => 42 }])
        end
      end
    end

    describe '#list with a filter' do
      before { stub_request(:post, "#{base}/issues/search").to_return(json('data' => [issue_payload('i1')])) }

      it 'sends the translated condition tree to the search endpoint' do
        collection.list(nil, filter(condition_tree: leaf('state', operators::EQUAL, 'closed')), %w[id])

        expect(WebMock).to have_requested(:post, "#{base}/issues/search").with(
          body: { 'limit' => Client::MAX_SEARCH_LIMIT,
                  'filter' => { 'field' => 'state', 'operator' => 'equals', 'value' => 'closed' } }
        )
      end

      it 'sends a free-text search as search_text, intersected with the filter' do
        query = filter(condition_tree: leaf('team_id', operators::EQUAL, 'team-1'), search: 'boom')

        collection.list(nil, query, %w[id])

        expect(WebMock).to have_requested(:post, "#{base}/issues/search").with(
          body: { 'limit' => Client::MAX_SEARCH_LIMIT, 'search_text' => 'boom',
                  'filter' => { 'field' => 'team_id', 'operator' => 'equals', 'value' => 'team-1' } }
        )
      end

      # The whole point of translating rather than dropping: a predicate Pylon
      # cannot express fails loudly instead of returning unfiltered rows.
      it 'raises rather than returning unfiltered rows for a predicate Pylon refuses' do
        expect { collection.list(nil, filter(condition_tree: leaf('number', operators::EQUAL, 12)), %w[id]) }
          .to raise_error(UnsupportedOperatorError, /cannot filter on 'number'/)
        expect(WebMock).not_to have_requested(:post, "#{base}/issues/search")
      end

      # Declaring the four ManyToOne relations is what makes a filter on a
      # related field reachable, and the schema advertises it as filterable.
      # Pylon has no join, so it is answered by reading the accounts matching
      # the condition and sending their ids as the `account_id` filter the
      # issues endpoint does take.
      it 'answers a filter on a related field with the keys of the matching records' do
        stub_request(:post, "#{base}/accounts/search")
          .to_return(json('data' => [{ 'id' => 'acc-1' }, { 'id' => 'acc-2' }]))
        stub_request(:post, "#{base}/issues/search").to_return(json('data' => []))

        collection.list(nil, filter(condition_tree: leaf('account:name', operators::CONTAINS, 'Acme')), %w[id])

        expect(WebMock).to have_requested(:post, "#{base}/accounts/search").with(
          body: hash_including('filter' => { 'field' => 'name', 'operator' => 'string_contains',
                                             'value' => 'Acme' })
        )
        expect(WebMock).to have_requested(:post, "#{base}/issues/search").with(
          body: hash_including('filter' => { 'field' => 'account_id', 'operator' => 'in',
                                             'values' => %w[acc-1 acc-2] })
        )
      end

      # No account matched, so no issue can: answered without asking the issues
      # endpoint, where an empty `in` would have read as no filter at all.
      it 'answers with no issue when no related record matched, without searching' do
        stub_request(:post, "#{base}/accounts/search").to_return(json('data' => []))

        expect(collection.list(nil, filter(condition_tree: leaf('account:name', operators::CONTAINS, 'Acme')),
                               %w[id])).to eq([])
        expect(WebMock).not_to have_requested(:post, "#{base}/issues/search")
      end

      # Resolved before the short-circuit reads the tree, so the relation
      # becomes an `account_id in [...]` the id lookup can apply in memory.
      it 'resolves a filter on a related field combined with an id' do
        stub_request(:post, "#{base}/accounts/search").to_return(json('data' => [{ 'id' => 'acc-1' }]))
        stub_request(:get, "#{base}/issues/i1").to_return(json('data' => issue_payload('i1')))
        conditions = [id_leaf(operators::EQUAL, 'i1'), leaf('account:name', operators::CONTAINS, 'Acme')]

        expect(collection.list(nil, filter(condition_tree: branch('And', conditions)), %w[id]))
          .to eq([{ 'id' => 'i1' }])
      end

      # A relation the filter never names costs nothing: no foreign read is
      # triggered by declaring it.
      it 'reads no foreign collection for a filter naming none' do
        stub_request(:post, "#{base}/issues/search").to_return(json('data' => []))

        collection.list(nil, filter(condition_tree: leaf('state', operators::EQUAL, 'new')), %w[id])

        expect(WebMock).not_to have_requested(:post, "#{base}/accounts/search")
      end

      it 'keeps the same filter across every page of the walk' do
        stub_request(:post, "#{base}/issues/search")
          .with(body: hash_including('limit' => 3))
          .to_return(json('data' => [issue_payload('i1'), issue_payload('i2')],
                          'pagination' => { 'cursor' => 'c1', 'has_next_page' => true }))
        stub_request(:post, "#{base}/issues/search")
          .with(body: hash_including('cursor' => 'c1'))
          .to_return(json('data' => [issue_payload('i3')]))
        query = filter(condition_tree: leaf('state', operators::EQUAL, 'new'), page: page(2, 1))

        expect(collection.list(nil, query, %w[id])).to eq([{ 'id' => 'i3' }])
        expect(WebMock).to have_requested(:post, "#{base}/issues/search")
          .with(body: hash_including('filter' => { 'field' => 'state', 'operator' => 'equals',
                                                   'value' => 'new' })).twice
      end
    end

    describe '#list on a primary-key lookup carrying more conditions' do
      # Forest sends `AND(id equal X, <scope>)` on a record detail as soon as a
      # scope or a segment is set; `id` is not a Pylon filter field, so the
      # lookup has to survive the extra conditions.
      it 'reads the issue by id and applies the leftover conditions in memory' do
        stub_request(:get, "#{base}/issues/i1").to_return(json('data' => issue_payload('i1')))
        tree = branch('And', [id_leaf(operators::EQUAL, 'i1'), leaf('state', operators::EQUAL, 'new')])

        expect(collection.list(nil, filter(condition_tree: tree), %w[id])).to eq([{ 'id' => 'i1' }])
        expect(WebMock).not_to have_requested(:post, "#{base}/issues/search")
      end

      it 'drops the record when a leftover condition does not match' do
        stub_request(:get, "#{base}/issues/i1").to_return(json('data' => issue_payload('i1')))
        tree = branch('And', [id_leaf(operators::EQUAL, 'i1'), leaf('state', operators::EQUAL, 'closed')])

        expect(collection.list(nil, filter(condition_tree: tree), %w[id])).to eq([])
      end

      # Which records the window holds is only known once the residual has run,
      # so `records_by_id` applies it first and slices second. Slicing the ids
      # first would cut this page out of i1..i3 and then drop i1 from it -- a
      # page answered with the records left over, silently missing i3.
      it 'applies the leftover conditions before it cuts the page window' do
        %w[i1 i2 i3].each do |id|
          state = id == 'i1' ? 'closed' : 'new'
          stub_request(:get, "#{base}/issues/#{id}").to_return(json('data' => issue_payload(id, 'state' => state)))
        end
        tree = branch('And', [id_leaf(operators::IN, %w[i1 i2 i3]), leaf('state', operators::EQUAL, 'new')])

        rows = collection.list(nil, filter(condition_tree: tree, page: page(1, 1)), %w[id])

        expect(rows).to eq([{ 'id' => 'i3' }])
      end

      # `tags` holds a list whose Pylon membership semantics have no in-memory
      # counterpart: the lookup is refused rather than silently mis-filtered.
      it 'refuses a leftover condition it cannot evaluate in memory' do
        tree = branch('And', [id_leaf(operators::EQUAL, 'i1'), leaf('tags', operators::CONTAINS, 'urgent')])

        expect { collection.list(nil, filter(condition_tree: tree), %w[id]) }
          .to raise_error(UnsupportedOperatorError, /cannot be combined with a primary-key lookup/)
        expect(WebMock).not_to have_requested(:get, "#{base}/issues/i1")
      end

      # An unresolved issue carries `resolution_time: nil`, and a bare `nil >
      # value` raises: a scope or a segment dated on that column used to turn
      # every record detail it did not match into a 500.
      it 'excludes the record instead of raising when a dated condition meets a null column' do
        stub_request(:get, "#{base}/issues/i1").to_return(json('data' => issue_payload('i1')))
        tree = branch('And', [id_leaf(operators::EQUAL, 'i1'),
                              leaf('resolution_time', operators::GREATER_THAN, '2026-01-01T00:00:00Z')])

        expect(collection.list(nil, filter(condition_tree: tree), %w[id])).to eq([])
      end

      it 'keeps the record when the dated condition matches' do
        stub_request(:get, "#{base}/issues/i1")
          .to_return(json('data' => issue_payload('i1', 'resolution_time' => '2026-08-07T13:06:22Z')))
        tree = branch('And', [id_leaf(operators::EQUAL, 'i1'),
                              leaf('resolution_time', operators::GREATER_THAN, '2026-01-01T00:00:00Z')])

        expect(collection.list(nil, filter(condition_tree: tree), %w[id])).to eq([{ 'id' => 'i1' }])
      end
    end

    describe '#list on a primary-key lookup carrying a search' do
      # The short-circuit never reaches /issues/search, so honouring the search
      # is impossible: returning the record unsearched would be a result that
      # looks searched and is not.
      it 'refuses to answer rather than dropping the search' do
        query = filter(condition_tree: id_leaf(operators::EQUAL, 'i1'), search: 'boom')

        expect { collection.list(nil, query, %w[id]) }
          .to raise_error(UnsupportedOperatorError, /search cannot be combined with a filter on 'id'/)
        expect(WebMock).not_to have_requested(:get, "#{base}/issues/i1")
      end

      it 'still serves the lookup when the search is empty' do
        stub_request(:get, "#{base}/issues/i1").to_return(json('data' => issue_payload('i1')))
        query = filter(condition_tree: id_leaf(operators::EQUAL, 'i1'), search: '')

        expect(collection.list(nil, query, %w[id])).to eq([{ 'id' => 'i1' }])
      end
    end

    describe '#list on a primary-key lookup of many ids' do
      # One GET per id against the same 20 req/min budget the cursor walk is
      # capped for, so the fan-out is bounded the same way.
      it 'reads at most the capped number of ids and warns' do
        allow(ForestAdminDatasourcePylon.logger).to receive(:warn)
        ids = Array.new(Collections::Issue::MAX_ID_LOOKUPS + 5) { |i| "i#{i}" }
        ids.each { |id| stub_request(:get, "#{base}/issues/#{id}").to_return(json('data' => issue_payload(id))) }

        rows = collection.list(nil, filter(condition_tree: id_leaf(operators::IN, ids)), %w[id])

        expect(rows.size).to eq(Collections::Issue::MAX_ID_LOOKUPS)
        expect(ForestAdminDatasourcePylon.logger).to have_received(:warn).with(/reading the first 20/)
      end

      it 'stays quiet and reads every id under the cap' do
        allow(ForestAdminDatasourcePylon.logger).to receive(:warn)
        %w[i1 i2].each { |id| stub_request(:get, "#{base}/issues/#{id}").to_return(json('data' => issue_payload(id))) }

        collection.list(nil, filter(condition_tree: id_leaf(operators::IN, %w[i1 i2])), %w[id])

        expect(ForestAdminDatasourcePylon.logger).not_to have_received(:warn)
      end
    end

    describe '#list with a sort' do
      before do
        allow(ForestAdminDatasourcePylon.logger).to receive(:warn)
        stub_request(:post, "#{base}/issues/search").to_return(json('data' => [issue_payload('i1')]))
      end

      # /issues/search has no sort parameter, so the order is reported instead of
      # being silently swallowed.
      it 'warns that the requested order cannot be honoured' do
        sort = ForestAdminDatasourceToolkit::Components::Query::Sort
               .new([{ field: 'created_at', ascending: true }])

        collection.list(nil, filter(sort: sort), %w[id])

        expect(ForestAdminDatasourcePylon.logger).to have_received(:warn).with(/cannot honour the requested order/)
      end

      it 'stays quiet when Forest asks for no order' do
        collection.list(nil, filter, %w[id])

        expect(ForestAdminDatasourcePylon.logger).not_to have_received(:warn)
      end

      # The agent injects an ascending primary-key sort whenever the request
      # asks for no order; only an order someone actually chose is reported.
      it 'stays quiet on the default primary-key sort the agent injects' do
        sort = ForestAdminDatasourceToolkit::Components::Query::Sort.new([{ field: 'id', ascending: true }])

        collection.list(nil, filter(sort: sort), %w[id])

        expect(ForestAdminDatasourcePylon.logger).not_to have_received(:warn)
      end

      it 'warns on a chosen order, even one on the primary key' do
        sort = ForestAdminDatasourceToolkit::Components::Query::Sort.new([{ field: 'id', ascending: false }])

        collection.list(nil, filter(sort: sort), %w[id])

        expect(ForestAdminDatasourcePylon.logger).to have_received(:warn).with(/cannot honour the requested order/)
      end

      # The lookup returns the records in the order of the ids, so an order the
      # operator chose is just as unhonoured there as on the search path.
      it 'warns on the primary-key path too' do
        stub_request(:get, "#{base}/issues/i1").to_return(json('data' => issue_payload('i1')))
        sort = ForestAdminDatasourceToolkit::Components::Query::Sort
               .new([{ field: 'created_at', ascending: true }])

        collection.list(nil, filter(condition_tree: id_leaf(operators::EQUAL, 'i1'), sort: sort), %w[id])

        expect(ForestAdminDatasourcePylon.logger).to have_received(:warn).with(/cannot honour the requested order/)
      end
    end
  end
end
