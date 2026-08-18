module ForestAdminDatasourcePylon
  RSpec.describe Collections::Account do
    def filter(condition_tree: nil, search: nil, page: nil, sort: nil)
      ForestAdminDatasourceToolkit::Components::Query::Filter.new(
        condition_tree: condition_tree, search: search, page: page, sort: sort
      )
    end

    def leaf(field, operator, value = nil)
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

    def sort_on(field, ascending: true)
      ForestAdminDatasourceToolkit::Components::Query::Sort.new([{ field: field, ascending: ascending }])
    end

    def json(payload, status = 200)
      { status: status, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end

    # Trimmed to the shape observed on the API: the owner is a nested object
    # carrying an id, and unset values come back as null rather than absent.
    def account_payload(id, overrides = {})
      {
        'id' => id, 'name' => 'Acme', 'type' => 'customer', 'is_disabled' => false,
        'domain' => 'acme.com', 'primary_domain' => 'acme.com', 'domains' => %w[acme.com acme.io],
        'tags' => %w[vip], 'owner' => { 'id' => 'usr-1', 'email' => 'ada@acme.com' },
        'external_ids' => [{ 'external_id' => 'crm-1', 'label' => 'salesforce' }],
        'channels' => [{ 'channel_id' => 'C1', 'source' => 'slack', 'is_primary' => true }],
        'crm_settings' => { 'details' => [{ 'id' => 'crm-1', 'source' => 'salesforce' }] },
        'custom_fields' => {}, 'created_at' => '2026-08-07T13:06:22Z', 'updated_at' => '2026-08-10T09:00:00Z',
        'latest_customer_activity_time' => nil
      }.merge(overrides)
    end

    # Relations are fields too; the assertions on the columns select them out.
    def columns
      collection.fields.select { |_name, field| field.type == 'Column' }
    end

    let(:datasource) { ForestAdminDatasourcePylon::Datasource.new(api_key: 'k') }
    let(:collection) { described_class.new(datasource) }
    let(:base) { datasource.configuration.url }
    let(:operators) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators }

    def stub_list(query, payload)
      stub_request(:get, "#{base}/accounts").with(query: query).to_return(json(payload))
    end

    def stub_search(payload = { 'data' => [account_payload('acc-1')] })
      stub_request(:post, "#{base}/accounts/search").to_return(json(payload))
    end

    describe 'schema' do
      it 'is named PylonAccount' do
        expect(collection.name).to eq('PylonAccount')
      end

      it 'declares id as the primary key' do
        expect(collection.fields['id'].is_primary_key).to be(true)
      end

      # No short-circuit to serve here: /accounts/search filters id itself, so
      # the column advertises every operator the endpoint accepts on it.
      it 'advertises the id operators the search endpoint filters server-side' do
        expect(collection.fields['id'].filter_operators)
          .to eq([operators::EQUAL, operators::IN, operators::NOT_IN])
      end

      it 'exposes the native columns observed on the API' do
        expect(collection.fields.keys).to include(
          'name', 'type', 'is_disabled', 'domain', 'primary_domain', 'domains', 'tags',
          'owner_id', 'external_ids', 'channels', 'crm_settings',
          'created_at', 'updated_at', 'latest_customer_activity_time'
        )
      end

      it 'flattens the owner into a foreign-key column instead of exposing the nested object' do
        expect(collection.fields.keys).not_to include('owner')
      end

      it 'types the lists as Json and the times as dates' do
        expect(collection.fields['domains'].column_type).to eq('Json')
        expect(collection.fields['channels'].column_type).to eq('Json')
        expect(collection.fields['is_disabled'].column_type).to eq('Boolean')
        expect(collection.fields['latest_customer_activity_time'].column_type).to eq('Date')
      end

      # Neither endpoint exposes a sort parameter, and writes land in a later story.
      it 'declares every column read-only and non-sortable' do
        expect(columns.values.map(&:is_read_only).uniq).to eq([true])
        expect(columns.values.map(&:is_sortable).uniq).to eq([false])
      end

      # No Pylon endpoint aggregates, and the pages of a cursor walk are not the
      # dataset: a chart grouped by one of these columns would answer a fraction
      # as if it were the whole collection.
      it 'declares no column groupable' do
        expect(columns.values.map(&:is_groupable).uniq).to eq([false])
      end

      # `search_text` is native on /accounts/search, while Pylon exposes neither a
      # count endpoint nor a total, so Count stays out until it can be throttled.
      it 'enables search and leaves count disabled' do
        expect(collection.is_searchable?).to be(true)
        expect(collection.is_countable?).to be(false)
      end

      it 'advertises only the operators the search allow-list accepts' do
        expect(collection.fields['name'].filter_operators)
          .to eq([operators::EQUAL, operators::IN, operators::NOT_IN, operators::CONTAINS, operators::I_CONTAINS])
        expect(collection.fields['owner_id'].filter_operators)
          .to eq([operators::EQUAL, operators::IN, operators::NOT_IN,
                  operators::PRESENT, operators::BLANK, operators::MISSING])
        expect(collection.fields['tags'].filter_operators)
          .to eq([operators::IN, operators::NOT_IN])
        expect(collection.fields['domains'].filter_operators)
          .to eq([operators::IN, operators::NOT_IN])
      end

      # `POST /accounts/search` does filter a list column with `contains`, and
      # the schema still must not advertise it: the column is typed Json, the
      # only type the toolkit has for a list, and it allows no substring
      # operator on one -- the filter would be refused on the way in.
      it 'advertises no substring operator on a list column' do
        allowed = ForestAdminDatasourceToolkit::Validations::Rules.get_allowed_operators_for_column_type('Json')

        %w[domains tags].each do |field|
          expect(collection.fields[field].filter_operators)
            .not_to include(operators::CONTAINS, operators::NOT_CONTAINS, operators::I_CONTAINS)
          expect(allowed).to include(*collection.fields[field].filter_operators)
        end
      end

      # /accounts/search accepts `string_contains` on a name but documents no
      # negation of it, so the UI must not offer one.
      it 'offers no negated substring on name' do
        expect(collection.fields['name'].filter_operators)
          .not_to include(operators::NOT_CONTAINS, operators::NOT_I_CONTAINS)
      end

      # The endpoint does filter external_ids, on the bare id strings, while the
      # column shows { external_id, label } objects: the filter would run on
      # something the operator cannot see.
      it 'advertises no operator on external_ids' do
        expect(collection.fields['external_ids'].filter_operators).to eq([])
      end

      # Unlike /issues/search, the accounts search takes no time filter at all.
      it 'advertises no operator on the time columns' do
        %w[created_at updated_at latest_customer_activity_time].each do |field|
          expect(collection.fields[field].filter_operators).to eq([])
        end
      end

      it 'advertises no operator on the other columns Pylon cannot filter' do
        %w[domain primary_domain type is_disabled channels crm_settings].each do |field|
          expect(collection.fields[field].filter_operators).to eq([])
        end
      end
    end

    describe 'relations' do
      let(:one_to_many) { ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema }

      # The reverse sides of the ManyToOne relations Issue and Contact declare.
      # Both endpoints filter `account_id` server-side, so a related list is one
      # request and no in-memory pass.
      it 'declares the issues and the contacts of an account as OneToMany relations' do
        expect(collection.fields.values_at('issues', 'contacts')).to all(be_a(one_to_many))
        expect(collection.fields['issues'])
          .to have_attributes(foreign_collection: 'PylonIssue', origin_key: 'account_id',
                              origin_key_target: 'id')
        expect(collection.fields['contacts'])
          .to have_attributes(foreign_collection: 'PylonContact', origin_key: 'account_id',
                              origin_key_target: 'id')
      end

      # It points at a PylonUser, but nothing in the panel asks for the owner of
      # an account yet.
      it 'leaves the owner a plain column' do
        expect(collection.fields['owner_id'].type).to eq('Column')
        expect(collection.fields.keys).not_to include('owner')
      end
    end

    # No condition tree and no search: the listing endpoint returns the same
    # records for 60 requests per minute where the search endpoint allows 20.
    describe '#list without a filter' do
      it 'browses the listing endpoint and serializes what it returns' do
        stub_list({ 'limit' => '1000' }, 'data' => [account_payload('acc-1')])

        rows = collection.list(nil, filter, nil)

        expect(rows.size).to eq(1)
        expect(rows.first).to include('id' => 'acc-1', 'name' => 'Acme', 'type' => 'customer',
                                      'domains' => %w[acme.com acme.io], 'tags' => %w[vip],
                                      'is_disabled' => false, 'latest_customer_activity_time' => nil)
      end

      it 'flattens the nested owner into a foreign-key column' do
        stub_list({ 'limit' => '1000' }, 'data' => [account_payload('acc-1')])

        expect(collection.list(nil, filter, nil).first).to include('owner_id' => 'usr-1')
      end

      it 'keeps the nested object out of the serialized record' do
        stub_list({ 'limit' => '1000' }, 'data' => [account_payload('acc-1')])

        expect(collection.list(nil, filter, nil).first.keys).not_to include('owner')
      end

      it 'reports no owner rather than raising when the account has none' do
        stub_list({ 'limit' => '1000' }, 'data' => [account_payload('acc-1', 'owner' => nil)])

        expect(collection.list(nil, filter, nil).first).to include('owner_id' => nil)
      end

      it 'restricts the record to the projection' do
        stub_list({ 'limit' => '1000' }, 'data' => [account_payload('acc-1')])

        expect(collection.list(nil, filter, %w[id name])).to eq([{ 'id' => 'acc-1', 'name' => 'Acme' }])
      end

      it 'never spends the search budget' do
        stub_list({ 'limit' => '1000' }, 'data' => [account_payload('acc-1')])

        collection.list(nil, filter, %w[id])

        expect(WebMock).not_to have_requested(:post, "#{base}/accounts/search")
      end

      # The search box sends an empty string once the operator clears it, which
      # is not a search and must not cost a search request.
      it 'browses when the search is blank' do
        stub_list({ 'limit' => '1000' }, 'data' => [account_payload('acc-1')])

        expect(collection.list(nil, filter(search: '  '), %w[id])).to eq([{ 'id' => 'acc-1' }])
      end

      it 'browses when Forest sends no filter at all' do
        stub_list({ 'limit' => '1000' }, 'data' => [account_payload('acc-1')])

        expect(collection.list(nil, nil, %w[id])).to eq([{ 'id' => 'acc-1' }])
      end

      it 'forwards the requested page as the listing limit' do
        stub_list({ 'limit' => '1' }, 'data' => [account_payload('acc-1')])

        collection.list(nil, filter(page: page(0, 1)), nil)

        expect(WebMock).to have_requested(:get, "#{base}/accounts").with(query: { 'limit' => '1' })
      end

      it 'walks the cursor until the requested window is covered' do
        stub_list({ 'limit' => '3' },
                  'data' => [account_payload('acc-1'), account_payload('acc-2')],
                  'pagination' => { 'cursor' => 'c1', 'has_next_page' => true })
        stub_list({ 'limit' => '1', 'cursor' => 'c1' }, 'data' => [account_payload('acc-3')])

        expect(collection.list(nil, filter(page: page(2, 1)), %w[id])).to eq([{ 'id' => 'acc-3' }])
      end

      it 'returns an empty list when the organization has no account' do
        stub_list({ 'limit' => '1000' }, 'data' => [])

        expect(collection.list(nil, filter, nil)).to eq([])
      end
    end

    describe '#list with a filter' do
      before { stub_search }

      it 'sends the translated condition tree to the search endpoint' do
        collection.list(nil, filter(condition_tree: leaf('name', operators::I_CONTAINS, 'acm')), %w[id])

        expect(WebMock).to have_requested(:post, "#{base}/accounts/search").with(
          body: { 'limit' => Client::MAX_SEARCH_LIMIT,
                  'filter' => { 'field' => 'name', 'operator' => 'string_contains', 'value' => 'acm' } }
        )
      end

      it 'translates a membership filter on a list column' do
        collection.list(nil, filter(condition_tree: leaf('tags', operators::IN, %w[vip])), %w[id])

        expect(WebMock).to have_requested(:post, "#{base}/accounts/search").with(
          body: hash_including('filter' => { 'field' => 'tags', 'operator' => 'in', 'values' => %w[vip] })
        )
      end

      it 'translates a presence filter with no value' do
        collection.list(nil, filter(condition_tree: leaf('owner_id', operators::BLANK)), %w[id])

        expect(WebMock).to have_requested(:post, "#{base}/accounts/search").with(
          body: hash_including('filter' => { 'field' => 'owner_id', 'operator' => 'is_unset' })
        )
      end

      it 'sends a free-text search as search_text, intersected with the filter' do
        query = filter(condition_tree: leaf('tags', operators::IN, %w[vip]), search: 'acme')

        collection.list(nil, query, %w[id])

        expect(WebMock).to have_requested(:post, "#{base}/accounts/search").with(
          body: { 'limit' => Client::MAX_SEARCH_LIMIT, 'search_text' => 'acme',
                  'filter' => { 'field' => 'tags', 'operator' => 'in', 'values' => %w[vip] } }
        )
      end

      # The listing endpoint cannot search, so a search alone is worth the
      # search endpoint even with nothing to filter.
      it 'searches on a free-text search alone' do
        collection.list(nil, filter(search: 'acme'), %w[id])

        expect(WebMock).to have_requested(:post, "#{base}/accounts/search")
          .with(body: { 'limit' => Client::MAX_SEARCH_LIMIT, 'search_text' => 'acme' })
        expect(WebMock).not_to have_requested(:get, "#{base}/accounts")
      end

      # `id` is a filter field of this endpoint, so it needs no short-circuit and
      # an `or` cannot widen anything: it is translated like any other field.
      it 'translates an id filter server-side, even under an or' do
        tree = branch('Or', [id_leaf(operators::EQUAL, 'acc-1'), leaf('name', operators::EQUAL, 'Acme')])

        collection.list(nil, filter(condition_tree: tree), %w[id])

        expect(WebMock).to have_requested(:post, "#{base}/accounts/search").with(
          body: hash_including(
            'filter' => { 'operator' => 'or',
                          'subfilters' => [{ 'field' => 'id', 'operator' => 'equals', 'value' => 'acc-1' },
                                           { 'field' => 'name', 'operator' => 'equals', 'value' => 'Acme' }] }
          )
        )
      end

      # The whole point of translating rather than dropping: a predicate Pylon
      # cannot express fails loudly instead of returning unfiltered rows.
      it 'raises rather than returning unfiltered rows for a field Pylon cannot filter' do
        query = filter(condition_tree: leaf('created_at', operators::GREATER_THAN, '2026-01-01T00:00:00Z'))

        expect { collection.list(nil, query, %w[id]) }
          .to raise_error(UnsupportedOperatorError, /cannot filter on 'created_at'/)
        expect(WebMock).not_to have_requested(:post, "#{base}/accounts/search")
      end

      it 'raises rather than searching for an operator the endpoint refuses on a field' do
        expect { collection.list(nil, filter(condition_tree: leaf('name', operators::NOT_CONTAINS, 'a')), %w[id]) }
          .to raise_error(UnsupportedOperatorError, /not supported on field 'name'/)
      end

      it 'keeps the same filter across every page of the walk' do
        stub_request(:post, "#{base}/accounts/search")
          .with(body: hash_including('limit' => 3))
          .to_return(json('data' => [account_payload('acc-1'), account_payload('acc-2')],
                          'pagination' => { 'cursor' => 'c1', 'has_next_page' => true }))
        stub_request(:post, "#{base}/accounts/search")
          .with(body: hash_including('cursor' => 'c1'))
          .to_return(json('data' => [account_payload('acc-3')]))
        query = filter(condition_tree: leaf('tags', operators::IN, %w[vip]), page: page(2, 1))

        expect(collection.list(nil, query, %w[id])).to eq([{ 'id' => 'acc-3' }])
        expect(WebMock).to have_requested(:post, "#{base}/accounts/search")
          .with(body: hash_including('filter' => { 'field' => 'tags', 'operator' => 'in',
                                                   'values' => %w[vip] })).twice
      end
    end

    # A record detail is `id equals X` alone: reading it through GET
    # /accounts/{id} spends the 60 requests/minute budget instead of the 20 of
    # the search endpoint.
    describe '#list on a single-id filter' do
      it 'reads the account through its own endpoint instead of searching' do
        stub_request(:get, "#{base}/accounts/acc-1").to_return(json('data' => account_payload('acc-1')))

        rows = collection.list(nil, filter(condition_tree: id_leaf(operators::EQUAL, 'acc-1')), %w[id name])

        expect(rows).to eq([{ 'id' => 'acc-1', 'name' => 'Acme' }])
        expect(WebMock).not_to have_requested(:post, "#{base}/accounts/search")
      end

      it 'still reads by id when the search is empty' do
        stub_request(:get, "#{base}/accounts/acc-1").to_return(json('data' => account_payload('acc-1')))
        query = filter(condition_tree: id_leaf(operators::EQUAL, 'acc-1'), search: '')

        expect(collection.list(nil, query, %w[id])).to eq([{ 'id' => 'acc-1' }])
      end

      it 'reports no record when the account no longer exists' do
        stub_request(:get, "#{base}/accounts/gone").to_return(json({ 'message' => 'not found' }, 404))

        expect(collection.list(nil, filter(condition_tree: id_leaf(operators::EQUAL, 'gone')), %w[id])).to eq([])
      end

      # A blank body would otherwise serialize into a record whose every column,
      # id included, is null: a row the panel shows and cannot open.
      it 'reports no record rather than a blank one when Pylon answers with no data' do
        stub_request(:get, "#{base}/accounts/acc-1").to_return(status: 200, body: '')

        expect(collection.list(nil, filter(condition_tree: id_leaf(operators::EQUAL, 'acc-1')), %w[id])).to eq([])
      end

      # `GET /accounts/{id}` accepts an external id in place of the primary key
      # and answers with the account carrying its own UUID. The row would not
      # match the filter that asked for it, and the same filter combined with a
      # scope — which goes through the search endpoint — answers nothing.
      it 'reports no record when the endpoint answered an alias of the primary key' do
        stub_request(:get, "#{base}/accounts/crm-1").to_return(json('data' => account_payload('acc-1')))
        query = filter(condition_tree: id_leaf(operators::EQUAL, 'crm-1'))

        expect(collection.list(nil, query, %w[id name])).to eq([])
      end

      it 'propagates a failure that is not a missing record' do
        stub_request(:get, "#{base}/accounts/acc-1").to_return(json({ 'message' => 'boom' }, 500))

        expect { collection.list(nil, filter(condition_tree: id_leaf(operators::EQUAL, 'acc-1')), %w[id]) }
          .to raise_error(APIError)
      end

      it 'applies the requested page to the record it read' do
        stub_request(:get, "#{base}/accounts/acc-1").to_return(json('data' => account_payload('acc-1')))
        query = filter(condition_tree: id_leaf(operators::EQUAL, 'acc-1'), page: page(1, 1))

        expect(collection.list(nil, query, %w[id])).to eq([])
      end

      # One search request answers several ids exactly, where one GET per id
      # would burn the budget of the whole agent.
      it 'searches instead when several ids are asked for' do
        stub_search('data' => [account_payload('acc-1'), account_payload('acc-2')])

        rows = collection.list(nil, filter(condition_tree: id_leaf(operators::IN, %w[acc-1 acc-2])), %w[id])

        expect(rows).to eq([{ 'id' => 'acc-1' }, { 'id' => 'acc-2' }])
        expect(WebMock).to have_requested(:post, "#{base}/accounts/search").with(
          body: hash_including('filter' => { 'field' => 'id', 'operator' => 'in',
                                             'values' => %w[acc-1 acc-2] })
        )
      end

      # Forest sends `AND(id equal X, <scope>)` on a record detail as soon as a
      # scope or a segment is set. The search endpoint filters both server-side,
      # so nothing has to be applied in memory -- and a scope on a list column,
      # which no in-memory pass could evaluate, is answered rather than refused.
      it 'searches instead when the filter carries more conditions' do
        stub_search
        tree = branch('And', [id_leaf(operators::EQUAL, 'acc-1'), leaf('tags', operators::IN, %w[vip])])

        expect(collection.list(nil, filter(condition_tree: tree), %w[id])).to eq([{ 'id' => 'acc-1' }])
        expect(WebMock).to have_requested(:post, "#{base}/accounts/search").with(
          body: hash_including(
            'filter' => { 'operator' => 'and',
                          'subfilters' => [{ 'field' => 'id', 'operator' => 'equals', 'value' => 'acc-1' },
                                           { 'field' => 'tags', 'operator' => 'in', 'values' => %w[vip] }] }
          )
        )
      end

      # Both are honoured at once here, unlike on the collections whose endpoint
      # cannot filter an id: the search intersects the filter server-side.
      it 'searches instead when a search is combined with the id' do
        stub_search
        query = filter(condition_tree: id_leaf(operators::EQUAL, 'acc-1'), search: 'acme')

        expect(collection.list(nil, query, %w[id])).to eq([{ 'id' => 'acc-1' }])
        expect(WebMock).to have_requested(:post, "#{base}/accounts/search").with(
          body: { 'limit' => Client::MAX_SEARCH_LIMIT, 'search_text' => 'acme',
                  'filter' => { 'field' => 'id', 'operator' => 'equals', 'value' => 'acc-1' } }
        )
      end

      it 'searches instead when the id is filtered out rather than in' do
        stub_search
        collection.list(nil, filter(condition_tree: id_leaf(operators::NOT_IN, %w[acc-9])), %w[id])

        expect(WebMock).to have_requested(:post, "#{base}/accounts/search").with(
          body: hash_including('filter' => { 'field' => 'id', 'operator' => 'not_in', 'values' => %w[acc-9] })
        )
      end
    end

    describe 'custom fields' do
      let(:column) do
        ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(column_type: 'String',
                                                               filter_operators: [operators::EQUAL])
      end
      let(:collection) do
        described_class.new(datasource, custom_fields: [{ column_name: 'tier', schema: column },
                                                        { column_name: 'zones', schema: column }])
      end

      it 'serializes single- and multi-value custom fields' do
        fields = { 'tier' => { 'slug' => 'tier', 'value' => 'gold' },
                   'zones' => { 'slug' => 'zones', 'values' => %w[eu us] } }
        stub_list({ 'limit' => '1000' }, 'data' => [account_payload('acc-1', 'custom_fields' => fields)])

        expect(collection.list(nil, filter, nil).first).to include('tier' => 'gold', 'zones' => %w[eu us])
      end

      it 'yields nil for a custom field the account does not carry' do
        stub_list({ 'limit' => '1000' }, 'data' => [account_payload('acc-1', 'custom_fields' => nil)])

        expect(collection.list(nil, filter, nil).first).to include('tier' => nil, 'zones' => nil)
      end

      # Pylon accepts a custom-field slug as a filter field, with the operators
      # the integrator declared on the column.
      it 'filters a custom field through its slug' do
        stub_search('data' => [])

        collection.list(nil, filter(condition_tree: leaf('tier', operators::EQUAL, 'gold')), %w[id])

        expect(WebMock).to have_requested(:post, "#{base}/accounts/search")
          .with(body: hash_including('filter' => { 'field' => 'tier', 'operator' => 'equals',
                                                   'value' => 'gold' }))
      end

      it 'refuses an operator the custom field does not declare' do
        expect { collection.list(nil, filter(condition_tree: leaf('tier', operators::CONTAINS, 'go')), %w[id]) }
          .to raise_error(UnsupportedOperatorError, /not supported on field 'tier'/)
      end

      # Clamped at registration, so the schema never advertises an operator the
      # translator would refuse at query time.
      it 'drops a declared operator Pylon cannot honour on a custom field and warns' do
        allow(ForestAdminDatasourcePylon.logger).to receive(:warn)
        declared = ForestAdminDatasourceToolkit::Schema::ColumnSchema
                   .new(column_type: 'String', filter_operators: [operators::EQUAL, operators::STARTS_WITH])

        clamped = described_class.new(datasource, custom_fields: [{ column_name: 'tier', schema: declared }])

        expect(clamped.fields['tier'].filter_operators).to eq([operators::EQUAL])
        expect(ForestAdminDatasourcePylon.logger)
          .to have_received(:warn).with(/cannot honour on a custom field \(starts_with\)/)
      end
    end

    describe '#list with a sort' do
      before { allow(ForestAdminDatasourcePylon.logger).to receive(:warn) }

      # No Pylon endpoint of this collection takes a sort parameter, so the
      # order is reported instead of being silently swallowed.
      it 'warns that the requested order cannot be honoured, naming what happens instead' do
        stub_list({ 'limit' => '1000' }, 'data' => [account_payload('acc-1')])

        collection.list(nil, filter(sort: sort_on('name')), %w[id])

        expect(ForestAdminDatasourcePylon.logger)
          .to have_received(:warn).with(/PylonAccount cannot honour the requested order.+order the API imposes/)
      end

      it 'stays quiet when Forest asks for no order' do
        stub_list({ 'limit' => '1000' }, 'data' => [account_payload('acc-1')])

        collection.list(nil, filter, %w[id])

        expect(ForestAdminDatasourcePylon.logger).not_to have_received(:warn)
      end

      # The agent injects an ascending primary-key sort whenever the request asks
      # for no order; only an order someone actually chose is reported.
      it 'stays quiet on the default primary-key sort the agent injects' do
        stub_list({ 'limit' => '1000' }, 'data' => [account_payload('acc-1')])

        collection.list(nil, filter(sort: sort_on('id')), %w[id])

        expect(ForestAdminDatasourcePylon.logger).not_to have_received(:warn)
      end

      it 'warns on the search path too' do
        stub_search

        collection.list(nil, filter(condition_tree: leaf('name', operators::EQUAL, 'Acme'),
                                    sort: sort_on('id', ascending: false)), %w[id])

        expect(ForestAdminDatasourcePylon.logger).to have_received(:warn).with(/cannot honour the requested order/)
      end

      it 'warns on the record path too' do
        stub_request(:get, "#{base}/accounts/acc-1").to_return(json('data' => account_payload('acc-1')))

        collection.list(nil, filter(condition_tree: id_leaf(operators::EQUAL, 'acc-1'), sort: sort_on('name')),
                        %w[id])

        expect(ForestAdminDatasourcePylon.logger).to have_received(:warn).with(/cannot honour the requested order/)
      end
    end
  end
end
