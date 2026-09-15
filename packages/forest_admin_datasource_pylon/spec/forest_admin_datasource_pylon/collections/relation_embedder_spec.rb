module ForestAdminDatasourcePylon
  # Observed through the two list paths that embed: PylonIssue, whose four
  # ManyToOne relations reach both kinds of foreign collection, and PylonContact,
  # which embeds through the cursor-paginated pipeline.
  RSpec.describe Collections::RelationEmbedder do
    def filter(condition_tree: nil, search: nil, page: nil)
      ForestAdminDatasourceToolkit::Components::Query::Filter.new(
        condition_tree: condition_tree, search: search, page: page
      )
    end

    def json(payload, status = 200)
      { status: status, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end

    # Trimmed to what the embedder reads: the nested parties. The columns left
    # out serialize to nil, which is what Pylon returns for them anyway.
    def issue_payload(id, overrides = {})
      { 'id' => id, 'title' => 'Boom', 'account' => { 'id' => 'acc-1' },
        'requester' => { 'id' => 'con-1' }, 'assignee' => { 'id' => 'usr-1' },
        'team' => { 'id' => 'team-1' } }.merge(overrides)
    end

    def account_payload(id, overrides = {})
      { 'id' => id, 'name' => 'Acme', 'domains' => %w[acme.com],
        'owner' => { 'id' => 'usr-9', 'email' => 'ada@acme.com' } }.merge(overrides)
    end

    def contact_payload(id, overrides = {})
      { 'id' => id, 'name' => 'Ada', 'email' => 'ada@acme.com',
        'account' => { 'id' => 'acc-1' } }.merge(overrides)
    end

    def user_payload(id, overrides = {})
      { 'id' => id, 'name' => 'Alice', 'role' => { 'id' => 'role-1', 'name' => 'Admin' } }.merge(overrides)
    end

    def team_payload(id, overrides = {})
      { 'id' => id, 'name' => 'Support', 'users' => [{ 'id' => 'usr-1' }] }.merge(overrides)
    end

    def id_filter(values)
      { 'field' => 'id', 'operator' => 'in', 'values' => values }
    end

    def stub_issues(*payloads)
      stub_request(:post, "#{base}/issues/search").to_return(json('data' => payloads))
    end

    def stub_accounts(*payloads)
      stub_request(:post, "#{base}/accounts/search").to_return(json('data' => payloads))
    end

    def stub_contact_search(*payloads)
      stub_request(:post, "#{base}/contacts/search").to_return(json('data' => payloads))
    end

    def stub_contact_list(*payloads)
      stub_request(:get, "#{base}/contacts").with(query: { 'limit' => '1000' })
                                            .to_return(json('data' => payloads))
    end

    def stub_users(*payloads)
      stub_request(:get, "#{base}/users").with(query: { 'include_deactivated' => 'true' })
                                         .to_return(json('data' => payloads))
    end

    def stub_teams(*payloads)
      stub_request(:get, "#{base}/teams").to_return(json('data' => payloads))
    end

    # The columns the foreign collection declares, which is what its serializer
    # is expected to fill in on the embedded record.
    def columns_of(name)
      datasource.get_collection(name).fields.select { |_field, schema| schema.type == 'Column' }.keys
    end

    let(:datasource) { ForestAdminDatasourcePylon::Datasource.new(api_key: 'k') }
    let(:issues) { datasource.get_collection('PylonIssue') }
    let(:contacts) { datasource.get_collection('PylonContact') }
    let(:base) { datasource.configuration.url }

    before { stub_custom_fields }

    describe 'what the projection asks for' do
      before { stub_issues(issue_payload('i1')) }

      it 'resolves only the relations the projection names' do
        stub_accounts(account_payload('acc-1'))

        row = issues.list(nil, filter, %w[id account:name]).first

        expect(row['account']).to include('id' => 'acc-1', 'name' => 'Acme')
        expect(WebMock).to have_requested(:post, "#{base}/accounts/search")
        expect(WebMock).not_to have_requested(:post, "#{base}/contacts/search")
        expect(WebMock).not_to have_requested(:get, "#{base}/users")
        expect(WebMock).not_to have_requested(:get, "#{base}/teams")
      end

      it 'reads no foreign collection when the projection holds columns only' do
        rows = issues.list(nil, filter, %w[id title account_id])

        expect(rows).to eq([{ 'id' => 'i1', 'title' => 'Boom', 'account_id' => 'acc-1' }])
        expect(WebMock).not_to have_requested(:post, "#{base}/accounts/search")
      end

      # A nil projection returns every column and no relation: `list` is also
      # called that way by a count or an export.
      it 'reads no foreign collection when the projection is nil' do
        expect(issues.list(nil, filter, nil).first).not_to have_key('account')
        expect(WebMock).not_to have_requested(:post, "#{base}/accounts/search")
      end

      # `account_id` is a column of the projection, not a relation prefix.
      it 'embeds nothing for a projected column bearing a relation name' do
        expect(issues.list(nil, filter, %w[account_id]).first.keys).to eq(%w[account_id])
      end
    end

    describe 'the ids it asks for' do
      it 'asks for an id once however many rows point at it' do
        stub_issues(issue_payload('i1'), issue_payload('i2'), issue_payload('i3', 'account' => { 'id' => 'acc-2' }))
        stub_accounts(account_payload('acc-1'), account_payload('acc-2'))

        rows = issues.list(nil, filter, %w[id account:name])

        expect(rows.map { |row| row['account']['id'] }).to eq(%w[acc-1 acc-1 acc-2])
        expect(WebMock).to have_requested(:post, "#{base}/accounts/search")
          .with(body: hash_including('filter' => id_filter(%w[acc-1 acc-2]))).once
      end

      # Pylon documents no maximum on an `in` filter; the chunk keeps the request
      # body and the page answering it bounded.
      it 'chunks the ids, and asks for no more records than the chunk holds' do
        chunk = Collections::CursorCollection::ID_CHUNK_SIZE
        ids = (1..(chunk + 50)).map { |index| "acc-#{index}" }
        stub_issues(*ids.map { |id| issue_payload("i-#{id}", 'account' => { 'id' => id }) })
        stub_accounts

        issues.list(nil, filter, %w[id account:name])

        expect(WebMock).to have_requested(:post, "#{base}/accounts/search")
          .with(body: { 'limit' => chunk, 'filter' => id_filter(ids.first(chunk)) })
        expect(WebMock).to have_requested(:post, "#{base}/accounts/search")
          .with(body: { 'limit' => 50, 'filter' => id_filter(ids.last(50)) })
        expect(WebMock).to have_requested(:post, "#{base}/accounts/search").twice
      end

      it 'sends no request at all when every foreign key of the page is null' do
        stub_issues(issue_payload('i1', 'team' => nil))

        expect(issues.list(nil, filter, %w[id team:name]).first).to eq('id' => 'i1', 'team' => nil)
        expect(WebMock).not_to have_requested(:get, "#{base}/teams")
      end

      it 'leaves the null key out of the ids it asks for' do
        stub_issues(issue_payload('i1'), issue_payload('i2', 'account' => nil))
        stub_accounts(account_payload('acc-1'))

        rows = issues.list(nil, filter, %w[id account:name])

        expect(rows.map { |row| row['account'] }).to eq([rows.first['account'], nil])
        expect(WebMock).to have_requested(:post, "#{base}/accounts/search")
          .with(body: hash_including('filter' => id_filter(%w[acc-1])))
      end

      # A blank key would otherwise reach the `in` filter of the read, which
      # refuses a blank inside a list: one malformed key would fail the page.
      it 'leaves a blank key out of the ids it asks for, like a null one' do
        stub_issues(issue_payload('i1'), issue_payload('i2', 'account' => { 'id' => '' }))
        stub_accounts(account_payload('acc-1'))

        rows = issues.list(nil, filter, %w[id account:name])

        expect(rows.map { |row| row['account'] }).to eq([rows.first['account'], nil])
        expect(WebMock).to have_requested(:post, "#{base}/accounts/search")
          .with(body: hash_including('filter' => id_filter(%w[acc-1])))
      end

      it 'sends no request at all when every foreign key of the page is blank' do
        stub_issues(issue_payload('i1', 'team' => { 'id' => '' }))

        expect(issues.list(nil, filter, %w[id team:name]).first).to eq('id' => 'i1', 'team' => nil)
        expect(WebMock).not_to have_requested(:get, "#{base}/teams")
      end

      # Deleted, merged, or outside the scope of the token: the row says so
      # rather than carrying a blank record the panel would offer to open.
      it 'embeds no record for a foreign key the endpoint no longer answers' do
        stub_issues(issue_payload('i1'))
        stub_accounts

        expect(issues.list(nil, filter, %w[id account:name]).first).to eq('id' => 'i1', 'account' => nil)
      end
    end

    describe 'how it reads the foreign collections' do
      before { stub_issues(issue_payload('i1'), issue_payload('i2', 'assignee' => { 'id' => 'usr-2' })) }

      # `GET /users` and `GET /teams` hand back the complete dataset, so the ids
      # only pick rows out of one response.
      it 'reads an unpaginated collection once and indexes it by id' do
        stub_users(user_payload('usr-1'), user_payload('usr-2', 'name' => 'Bob'))

        rows = issues.list(nil, filter, %w[id assignee:name])

        expect(rows.map { |row| row['assignee']['name'] }).to eq(%w[Alice Bob])
        expect(WebMock).to have_requested(:get, "#{base}/users")
          .with(query: { 'include_deactivated' => 'true' }).once
      end

      # A chunk is asked for as a single page, and Pylon is free to answer it over
      # several: the ids left out of the first page are read from the next one
      # rather than reported as records that no longer exist.
      it 'follows the cursor when Pylon answers a chunk over several pages' do
        stub_issues(issue_payload('i1'), issue_payload('i2', 'account' => { 'id' => 'acc-2' }))
        stub_request(:post, "#{base}/accounts/search").with(body: hash_including('limit' => 2))
                                                      .to_return(json('data' => [account_payload('acc-1')],
                                                                      'pagination' => { 'cursor' => 'c1',
                                                                                        'has_next_page' => true }))
        stub_request(:post, "#{base}/accounts/search").with(body: hash_including('cursor' => 'c1'))
                                                      .to_return(json('data' => [account_payload('acc-2')]))

        rows = issues.list(nil, filter, %w[id account:name])

        expect(rows.map { |row| row['account']['id'] }).to eq(%w[acc-1 acc-2])
        expect(WebMock).to have_requested(:post, "#{base}/accounts/search").twice
      end

      # One read per foreign collection, and one collection per relation here:
      # nothing is shared, so the four are read side by side.
      it 'reads each foreign collection the projection reaches' do
        stub_accounts(account_payload('acc-1'))
        stub_contact_search(contact_payload('con-1'))
        stub_users(user_payload('usr-1'), user_payload('usr-2'))
        stub_teams(team_payload('team-1'))

        row = issues.list(nil, filter, %w[id account:name requester:name assignee:name team:name]).first

        expect(row.keys).to eq(%w[id account requester assignee team])
        expect(row['requester']).to include('id' => 'con-1', 'name' => 'Ada')
        expect(row['team']).to include('id' => 'team-1', 'name' => 'Support')
      end
    end

    describe 'the shape of the embedded record' do
      before { stub_issues(issue_payload('i1')) }

      # The foreign endpoint takes no field list, so the collection reads the
      # whole record and the projection is applied to it here. Serving all of it
      # would answer `team:name` with columns the projection excluded -- and the
      # agent redacts that projection per collection, so the excluded ones are
      # also the ones the caller may not read.
      it 'carries the projected fields of the foreign collection, and nothing else' do
        stub_teams(team_payload('team-1'))

        expect(issues.list(nil, filter, %w[id team:name]).first['team'])
          .to eq('id' => 'team-1', 'name' => 'Support')
      end

      it 'leaves out the columns of the foreign collection the projection did not name' do
        stub_accounts(account_payload('acc-1'))

        embedded = issues.list(nil, filter, %w[id account:name]).first['account']

        expect(embedded.keys).to match_array(%w[id name])
        expect(columns_of('PylonAccount') - embedded.keys).to include('crm_settings', 'external_ids')
      end

      # `with_pks` puts it in the projection the route sends, but a caller inside
      # the agent may project without it, and the id is what the serializer
      # builds the nested resource around.
      it 'keeps the primary key of the foreign record even when the projection leaves it out' do
        stub_teams(team_payload('team-1'))

        expect(issues.list(nil, filter, %w[id team:user_ids]).first['team'])
          .to eq('id' => 'team-1', 'user_ids' => %w[usr-1])
      end

      it 'flattens the nested objects of the foreign record the way its own list does' do
        stub_accounts(account_payload('acc-1'))
        stub_users(user_payload('usr-1'))

        row = issues.list(nil, filter, %w[id account:owner_id assignee:role_name]).first

        expect(row['account']).to eq('id' => 'acc-1', 'owner_id' => 'usr-9')
        expect(row['assignee']).to eq('id' => 'usr-1', 'role_name' => 'Admin')
      end
    end

    describe 'the order of the rows' do
      it 'writes each related record on its own row' do
        stub_issues(issue_payload('i1', 'account' => { 'id' => 'acc-2' }),
                    issue_payload('i2', 'account' => nil),
                    issue_payload('i3'))
        stub_accounts(account_payload('acc-1', 'name' => 'First'), account_payload('acc-2', 'name' => 'Second'))

        rows = issues.list(nil, filter, %w[id account:name])

        expect(rows.map { |row| row['id'] }).to eq(%w[i1 i2 i3])
        expect(rows.map { |row| row['account']&.fetch('name') }).to eq(['Second', nil, 'First'])
      end

      # The window is cut out before the relations are read, so the ids asked for
      # are those of the rows the operator sees.
      it 'reads the relations of the requested page only' do
        stub_issues(issue_payload('i1'), issue_payload('i2', 'account' => { 'id' => 'acc-2' }))
        stub_accounts(account_payload('acc-2'))
        page = ForestAdminDatasourceToolkit::Components::Query::Page.new(offset: 1, limit: 1)

        rows = issues.list(nil, filter(page: page), %w[id account:name])

        expect(rows.map { |row| row['id'] }).to eq(%w[i2])
        expect(WebMock).to have_requested(:post, "#{base}/accounts/search")
          .with(body: hash_including('filter' => id_filter(%w[acc-2])))
      end
    end

    # The cursor-paginated pipeline embeds the same way, on all three of its
    # paths: the listing endpoint, the search endpoint and the record endpoint.
    describe 'PylonContact#list' do
      it 'embeds the account of a browsed page' do
        stub_contact_list(contact_payload('con-1'))
        stub_accounts(account_payload('acc-1'))

        row = contacts.list(nil, filter, %w[id account:name]).first

        expect(row).to eq('id' => 'con-1', 'account' => row['account'])
        expect(row['account']).to include('id' => 'acc-1', 'name' => 'Acme')
      end

      it 'embeds the account of a searched page' do
        stub_contact_search(contact_payload('con-1'))
        stub_accounts(account_payload('acc-1'))

        row = contacts.list(nil, filter(search: 'ada'), %w[id account:name]).first

        expect(row['account']).to include('id' => 'acc-1')
      end

      it 'embeds the account of a record read through its own endpoint' do
        stub_request(:get, "#{base}/contacts/con-1").to_return(json('data' => contact_payload('con-1')))
        stub_accounts(account_payload('acc-1'))
        tree = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
               .new('id', ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::EQUAL, 'con-1')

        row = contacts.list(nil, filter(condition_tree: tree), %w[id account:name]).first

        expect(row['account']).to include('id' => 'acc-1')
      end
    end

    # A OneToMany is not embedded: the agent lists the far side with a query of
    # its own, filtered on the origin key -- which every reverse side here is
    # filterable on server-side. PylonUser and PylonTeam declare nothing else, so
    # they embed nothing at all.
    describe 'a collection declaring no ManyToOne' do
      it 'embeds nothing, and reads nothing besides its own endpoint' do
        stub_users(user_payload('usr-1'))

        rows = datasource.get_collection('PylonUser').list(nil, filter, %w[id assigned_issues:id])

        expect(rows).to eq([{ 'id' => 'usr-1' }])
        expect(WebMock).not_to have_requested(:post, "#{base}/issues/search")
      end
    end
  end
end
