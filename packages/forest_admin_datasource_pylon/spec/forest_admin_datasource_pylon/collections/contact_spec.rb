module ForestAdminDatasourcePylon
  RSpec.describe Collections::Contact do
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

    # Trimmed to the shape observed on the API: the account is a nested object
    # carrying an id, and unset values come back as null rather than absent.
    def contact_payload(id, overrides = {})
      {
        'id' => id, 'name' => 'Ada Lovelace', 'email' => 'ada@acme.com',
        'emails' => %w[ada@acme.com ada@acme.io], 'account' => { 'id' => 'acc-1', 'external_ids' => nil },
        'avatar_url' => 'https://usepylon.com/ada.png', 'portal_role' => 'admin', 'portal_role_id' => 'role-1',
        'primary_phone_number' => '+33100000000', 'phone_numbers' => %w[+33100000000],
        'external_ids' => [{ 'external_id' => 'crm-9', 'label' => 'hubspot' }],
        'integration_user_ids' => [{ 'id' => 'U1', 'source' => 'slack' }], 'custom_fields' => {}
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
      stub_request(:get, "#{base}/contacts").with(query: query).to_return(json(payload))
    end

    def stub_search(payload = { 'data' => [contact_payload('con-1')] })
      stub_request(:post, "#{base}/contacts/search").to_return(json(payload))
    end

    describe 'schema' do
      it 'is named PylonContact' do
        expect(collection.name).to eq('PylonContact')
      end

      it 'declares id as the primary key' do
        expect(collection.fields['id'].is_primary_key).to be(true)
      end

      # No short-circuit to serve here: /contacts/search filters id itself, so
      # the column advertises every operator the endpoint accepts on it.
      it 'advertises the id operators the search endpoint filters server-side' do
        expect(collection.fields['id'].filter_operators)
          .to eq([operators::EQUAL, operators::IN, operators::NOT_IN])
      end

      it 'exposes the native columns observed on the API' do
        expect(collection.fields.keys).to include(
          'name', 'email', 'emails', 'account_id', 'avatar_url', 'portal_role', 'portal_role_id',
          'primary_phone_number', 'phone_numbers', 'external_ids', 'integration_user_ids'
        )
      end

      # The nested object Pylon returns becomes the key column; the `account`
      # field of the schema is the relation read through that key.
      it 'flattens the account into a foreign-key column instead of exposing the nested object' do
        expect(columns.keys).to include('account_id')
        expect(columns.keys).not_to include('account')
      end

      # Pylon returns no timestamp at all on a contact.
      it 'declares no time column' do
        expect(columns.values.map(&:column_type)).not_to include('Date')
      end

      it 'types the lists as Json' do
        expect(collection.fields['emails'].column_type).to eq('Json')
        expect(collection.fields['phone_numbers'].column_type).to eq('Json')
        expect(collection.fields['integration_user_ids'].column_type).to eq('Json')
      end

      # Neither endpoint exposes a sort parameter, and writes land in a later story.
      it 'declares every column read-only and non-sortable' do
        expect(columns.values.map(&:is_read_only).uniq).to eq([true])
        expect(columns.values.map(&:is_sortable).uniq).to eq([false])
      end

      it 'enables search and leaves count disabled' do
        expect(collection.is_searchable?).to be(true)
        expect(collection.is_countable?).to be(false)
      end

      it 'advertises only the operators the search allow-list accepts' do
        expect(collection.fields['name'].filter_operators)
          .to eq([operators::EQUAL, operators::IN, operators::NOT_IN, operators::CONTAINS, operators::I_CONTAINS])
        expect(collection.fields['email'].filter_operators)
          .to eq([operators::EQUAL, operators::IN, operators::NOT_IN, operators::CONTAINS, operators::I_CONTAINS])
        expect(collection.fields['account_id'].filter_operators)
          .to eq([operators::EQUAL, operators::IN, operators::NOT_IN])
      end

      # /contacts/search accepts `string_contains` but documents no negation of
      # it, so the UI must not offer one.
      it 'offers no negated substring on name and email' do
        expect(collection.fields['name'].filter_operators)
          .not_to include(operators::NOT_CONTAINS, operators::NOT_I_CONTAINS)
        expect(collection.fields['email'].filter_operators)
          .not_to include(operators::NOT_CONTAINS, operators::NOT_I_CONTAINS)
      end

      # The endpoint filters no external id on a contact, and the column shows
      # { external_id, label } objects the filter would not match anyway.
      it 'advertises no operator on external_ids' do
        expect(collection.fields['external_ids'].filter_operators).to eq([])
      end

      # `email` filters the primary address only: the lists, the phone numbers
      # and the portal role are absent from the allow-list.
      it 'advertises no operator on the columns Pylon cannot filter' do
        %w[emails phone_numbers primary_phone_number avatar_url portal_role portal_role_id
           integration_user_ids].each do |field|
          expect(collection.fields[field].filter_operators).to eq([])
        end
      end
    end

    describe 'relations' do
      it 'points at the account of a contact through the flattened foreign key' do
        expect(collection.fields['account'])
          .to be_a(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
          .and have_attributes(foreign_collection: 'PylonAccount', foreign_key: 'account_id',
                               foreign_key_target: 'id')
      end

      # `requested_issues` rather than `issues`: a contact is the requester of an
      # issue, never its assignee -- that side belongs to PylonUser.
      it 'declares the issues a contact requested, read through requester_id' do
        expect(collection.fields['requested_issues'])
          .to be_a(ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema)
          .and have_attributes(foreign_collection: 'PylonIssue', origin_key: 'requester_id',
                               origin_key_target: 'id')
      end
    end

    # No condition tree and no search: the listing endpoint returns the same
    # records for 60 requests per minute where the search endpoint allows 20.
    describe '#list without a filter' do
      it 'browses the listing endpoint and serializes what it returns' do
        stub_list({ 'limit' => '1000' }, 'data' => [contact_payload('con-1')])

        rows = collection.list(nil, filter, nil)

        expect(rows.size).to eq(1)
        expect(rows.first).to include('id' => 'con-1', 'name' => 'Ada Lovelace', 'email' => 'ada@acme.com',
                                      'emails' => %w[ada@acme.com ada@acme.io], 'portal_role' => 'admin',
                                      'primary_phone_number' => '+33100000000')
      end

      it 'flattens the nested account into a foreign-key column' do
        stub_list({ 'limit' => '1000' }, 'data' => [contact_payload('con-1')])

        expect(collection.list(nil, filter, nil).first).to include('account_id' => 'acc-1')
      end

      it 'keeps the nested object out of the serialized record' do
        stub_list({ 'limit' => '1000' }, 'data' => [contact_payload('con-1')])

        expect(collection.list(nil, filter, nil).first.keys).not_to include('account')
      end

      it 'reports no account rather than raising when the contact has none' do
        stub_list({ 'limit' => '1000' }, 'data' => [contact_payload('con-1', 'account' => nil)])

        expect(collection.list(nil, filter, nil).first).to include('account_id' => nil)
      end

      it 'restricts the record to the projection' do
        stub_list({ 'limit' => '1000' }, 'data' => [contact_payload('con-1')])

        expect(collection.list(nil, filter, %w[id email]))
          .to eq([{ 'id' => 'con-1', 'email' => 'ada@acme.com' }])
      end

      it 'never spends the search budget' do
        stub_list({ 'limit' => '1000' }, 'data' => [contact_payload('con-1')])

        collection.list(nil, filter, %w[id])

        expect(WebMock).not_to have_requested(:post, "#{base}/contacts/search")
      end

      it 'walks the cursor until the requested window is covered' do
        stub_list({ 'limit' => '3' },
                  'data' => [contact_payload('con-1'), contact_payload('con-2')],
                  'pagination' => { 'cursor' => 'c1', 'has_next_page' => true })
        stub_list({ 'limit' => '1', 'cursor' => 'c1' }, 'data' => [contact_payload('con-3')])

        expect(collection.list(nil, filter(page: page(2, 1)), %w[id])).to eq([{ 'id' => 'con-3' }])
      end

      it 'returns an empty list when the organization has no contact' do
        stub_list({ 'limit' => '1000' }, 'data' => [])

        expect(collection.list(nil, filter, nil)).to eq([])
      end
    end

    describe '#list with a filter' do
      before { stub_search }

      it 'sends the translated condition tree to the search endpoint' do
        collection.list(nil, filter(condition_tree: leaf('email', operators::I_CONTAINS, '@acme')), %w[id])

        expect(WebMock).to have_requested(:post, "#{base}/contacts/search").with(
          body: { 'limit' => Client::MAX_SEARCH_LIMIT,
                  'filter' => { 'field' => 'email', 'operator' => 'string_contains', 'value' => '@acme' } }
        )
      end

      it 'translates a filter on the account the contact belongs to' do
        collection.list(nil, filter(condition_tree: leaf('account_id', operators::IN, %w[acc-1 acc-2])), %w[id])

        expect(WebMock).to have_requested(:post, "#{base}/contacts/search").with(
          body: hash_including('filter' => { 'field' => 'account_id', 'operator' => 'in',
                                             'values' => %w[acc-1 acc-2] })
        )
      end

      it 'sends a free-text search as search_text, intersected with the filter' do
        query = filter(condition_tree: leaf('name', operators::EQUAL, 'Ada Lovelace'), search: 'ada')

        collection.list(nil, query, %w[id])

        expect(WebMock).to have_requested(:post, "#{base}/contacts/search").with(
          body: { 'limit' => Client::MAX_SEARCH_LIMIT, 'search_text' => 'ada',
                  'filter' => { 'field' => 'name', 'operator' => 'equals', 'value' => 'Ada Lovelace' } }
        )
      end

      # The listing endpoint cannot search, so a search alone is worth the
      # search endpoint even with nothing to filter.
      it 'searches on a free-text search alone' do
        collection.list(nil, filter(search: 'ada'), %w[id])

        expect(WebMock).to have_requested(:post, "#{base}/contacts/search")
          .with(body: { 'limit' => Client::MAX_SEARCH_LIMIT, 'search_text' => 'ada' })
        expect(WebMock).not_to have_requested(:get, "#{base}/contacts")
      end

      # `id` is a filter field of this endpoint, so it needs no short-circuit and
      # an `or` cannot widen anything: it is translated like any other field.
      it 'translates an id filter server-side, even under an or' do
        tree = branch('Or', [id_leaf(operators::EQUAL, 'con-1'), leaf('email', operators::EQUAL, 'ada@acme.com')])

        collection.list(nil, filter(condition_tree: tree), %w[id])

        expect(WebMock).to have_requested(:post, "#{base}/contacts/search").with(
          body: hash_including(
            'filter' => { 'operator' => 'or',
                          'subfilters' => [{ 'field' => 'id', 'operator' => 'equals', 'value' => 'con-1' },
                                           { 'field' => 'email', 'operator' => 'equals',
                                             'value' => 'ada@acme.com' }] }
          )
        )
      end

      # The whole point of translating rather than dropping: a predicate Pylon
      # cannot express fails loudly instead of returning unfiltered rows.
      it 'raises rather than returning unfiltered rows for a field Pylon cannot filter' do
        query = filter(condition_tree: leaf('portal_role', operators::EQUAL, 'admin'))

        expect { collection.list(nil, query, %w[id]) }
          .to raise_error(UnsupportedOperatorError, /cannot filter on 'portal_role'/)
        expect(WebMock).not_to have_requested(:post, "#{base}/contacts/search")
      end

      it 'raises rather than searching for an operator the endpoint refuses on a field' do
        query = filter(condition_tree: leaf('email', operators::NOT_I_CONTAINS, '@acme'))

        expect { collection.list(nil, query, %w[id]) }
          .to raise_error(UnsupportedOperatorError, /not supported on field 'email'/)
      end
    end

    # A record detail is `id equals X` alone: reading it through GET
    # /contacts/{id} spends the 60 requests/minute budget instead of the 20 of
    # the search endpoint.
    describe '#list on a single-id filter' do
      it 'reads the contact through its own endpoint instead of searching' do
        stub_request(:get, "#{base}/contacts/con-1").to_return(json('data' => contact_payload('con-1')))

        rows = collection.list(nil, filter(condition_tree: id_leaf(operators::EQUAL, 'con-1')), %w[id name])

        expect(rows).to eq([{ 'id' => 'con-1', 'name' => 'Ada Lovelace' }])
        expect(WebMock).not_to have_requested(:post, "#{base}/contacts/search")
      end

      it 'reports no record when the contact no longer exists' do
        stub_request(:get, "#{base}/contacts/gone").to_return(json({ 'message' => 'not found' }, 404))

        expect(collection.list(nil, filter(condition_tree: id_leaf(operators::EQUAL, 'gone')), %w[id])).to eq([])
      end

      it 'propagates a failure that is not a missing record' do
        stub_request(:get, "#{base}/contacts/con-1").to_return(json({ 'message' => 'boom' }, 500))

        expect { collection.list(nil, filter(condition_tree: id_leaf(operators::EQUAL, 'con-1')), %w[id]) }
          .to raise_error(APIError)
      end

      it 'applies the requested page to the record it read' do
        stub_request(:get, "#{base}/contacts/con-1").to_return(json('data' => contact_payload('con-1')))
        query = filter(condition_tree: id_leaf(operators::EQUAL, 'con-1'), page: page(1, 1))

        expect(collection.list(nil, query, %w[id])).to eq([])
      end

      # One search request answers several ids exactly, where one GET per id
      # would burn the budget of the whole agent.
      it 'searches instead when several ids are asked for' do
        stub_search('data' => [contact_payload('con-1'), contact_payload('con-2')])

        rows = collection.list(nil, filter(condition_tree: id_leaf(operators::IN, %w[con-1 con-2])), %w[id])

        expect(rows).to eq([{ 'id' => 'con-1' }, { 'id' => 'con-2' }])
        expect(WebMock).to have_requested(:post, "#{base}/contacts/search").with(
          body: hash_including('filter' => { 'field' => 'id', 'operator' => 'in',
                                             'values' => %w[con-1 con-2] })
        )
      end

      # Forest sends `AND(id equal X, <scope>)` on a record detail as soon as a
      # scope or a segment is set; the search endpoint filters both server-side.
      it 'searches instead when the filter carries more conditions' do
        stub_search
        tree = branch('And', [id_leaf(operators::EQUAL, 'con-1'), leaf('account_id', operators::EQUAL, 'acc-1')])

        expect(collection.list(nil, filter(condition_tree: tree), %w[id])).to eq([{ 'id' => 'con-1' }])
        expect(WebMock).to have_requested(:post, "#{base}/contacts/search").with(
          body: hash_including(
            'filter' => { 'operator' => 'and',
                          'subfilters' => [{ 'field' => 'id', 'operator' => 'equals', 'value' => 'con-1' },
                                           { 'field' => 'account_id', 'operator' => 'equals',
                                             'value' => 'acc-1' }] }
          )
        )
      end

      it 'searches instead when a search is combined with the id' do
        stub_search
        query = filter(condition_tree: id_leaf(operators::EQUAL, 'con-1'), search: 'ada')

        expect(collection.list(nil, query, %w[id])).to eq([{ 'id' => 'con-1' }])
        expect(WebMock).to have_requested(:post, "#{base}/contacts/search").with(
          body: { 'limit' => Client::MAX_SEARCH_LIMIT, 'search_text' => 'ada',
                  'filter' => { 'field' => 'id', 'operator' => 'equals', 'value' => 'con-1' } }
        )
      end
    end

    describe 'custom fields' do
      let(:column) do
        ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(column_type: 'String',
                                                               filter_operators: [operators::EQUAL])
      end
      let(:collection) do
        described_class.new(datasource, custom_fields: [{ column_name: 'seniority', schema: column },
                                                        { column_name: 'products', schema: column }])
      end

      it 'serializes single- and multi-value custom fields' do
        fields = { 'seniority' => { 'slug' => 'seniority', 'value' => 'champion' },
                   'products' => { 'slug' => 'products', 'values' => %w[api portal] } }
        stub_list({ 'limit' => '1000' }, 'data' => [contact_payload('con-1', 'custom_fields' => fields)])

        expect(collection.list(nil, filter, nil).first)
          .to include('seniority' => 'champion', 'products' => %w[api portal])
      end

      it 'yields nil for a custom field the contact does not carry' do
        stub_list({ 'limit' => '1000' }, 'data' => [contact_payload('con-1', 'custom_fields' => nil)])

        expect(collection.list(nil, filter, nil).first).to include('seniority' => nil, 'products' => nil)
      end

      it 'filters a custom field through its slug' do
        stub_search('data' => [])

        collection.list(nil, filter(condition_tree: leaf('seniority', operators::EQUAL, 'champion')), %w[id])

        expect(WebMock).to have_requested(:post, "#{base}/contacts/search")
          .with(body: hash_including('filter' => { 'field' => 'seniority', 'operator' => 'equals',
                                                   'value' => 'champion' }))
      end

      it 'refuses an operator the custom field does not declare' do
        query = filter(condition_tree: leaf('seniority', operators::CONTAINS, 'cham'))

        expect { collection.list(nil, query, %w[id]) }
          .to raise_error(UnsupportedOperatorError, /not supported on field 'seniority'/)
      end

      # Clamped at registration, so the schema never advertises an operator the
      # translator would refuse at query time.
      it 'drops a declared operator Pylon cannot honour on a custom field and warns' do
        allow(ForestAdminDatasourcePylon.logger).to receive(:warn)
        declared = ForestAdminDatasourceToolkit::Schema::ColumnSchema
                   .new(column_type: 'String', filter_operators: [operators::EQUAL, operators::STARTS_WITH])

        clamped = described_class.new(datasource, custom_fields: [{ column_name: 'seniority', schema: declared }])

        expect(clamped.fields['seniority'].filter_operators).to eq([operators::EQUAL])
        expect(ForestAdminDatasourcePylon.logger)
          .to have_received(:warn).with(/cannot honour on a custom field \(starts_with\)/)
      end
    end

    describe '#list with a sort' do
      before { allow(ForestAdminDatasourcePylon.logger).to receive(:warn) }

      it 'warns that the requested order cannot be honoured, naming what happens instead' do
        stub_list({ 'limit' => '1000' }, 'data' => [contact_payload('con-1')])

        collection.list(nil, filter(sort: sort_on('email')), %w[id])

        expect(ForestAdminDatasourcePylon.logger)
          .to have_received(:warn).with(/PylonContact cannot honour the requested order.+order the API imposes/)
      end

      it 'stays quiet when Forest asks for no order and on the default primary-key sort' do
        stub_list({ 'limit' => '1000' }, 'data' => [contact_payload('con-1')])

        collection.list(nil, filter, %w[id])
        collection.list(nil, filter(sort: sort_on('id')), %w[id])

        expect(ForestAdminDatasourcePylon.logger).not_to have_received(:warn)
      end

      it 'warns on the search path too' do
        stub_search

        collection.list(nil, filter(condition_tree: leaf('email', operators::EQUAL, 'ada@acme.com'),
                                    sort: sort_on('name')), %w[id])

        expect(ForestAdminDatasourcePylon.logger).to have_received(:warn).with(/cannot honour the requested order/)
      end
    end
  end
end
