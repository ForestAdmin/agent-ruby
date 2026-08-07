module ForestAdminDatasourcePylon
  RSpec.describe Collections::Issue do
    def filter(condition_tree: nil, search: nil, page: nil)
      ForestAdminDatasourceToolkit::Components::Query::Filter.new(
        condition_tree: condition_tree, search: search, page: page
      )
    end

    def leaf(field, operator, value)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
        .new(field, operator, value)
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

    let(:datasource) { ForestAdminDatasourcePylon::Datasource.new(api_key: 'k') }
    let(:collection) { datasource.get_collection('PylonIssue') }
    let(:base) { datasource.configuration.url }
    let(:operators) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators }

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

      # /issues/search exposes no sort parameter, and writes land in a later story.
      it 'declares every column read-only and non-sortable' do
        expect(collection.fields.values.map(&:is_read_only).uniq).to eq([true])
        expect(collection.fields.values.map(&:is_sortable).uniq).to eq([false])
      end

      it 'leaves search and count disabled' do
        expect(collection.is_searchable?).to be(false)
        expect(collection.is_countable?).to be(false)
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
    end

    describe 'filters it cannot honour yet' do
      before do
        allow(ForestAdminDatasourcePylon.logger).to receive(:warn)
        stub_request(:post, "#{base}/issues/search").to_return(json('data' => [issue_payload('i1')]))
      end

      it 'warns and returns unfiltered records for a non primary-key condition' do
        tree = leaf('state', operators::EQUAL, 'closed')

        expect(collection.list(nil, filter(condition_tree: tree), %w[id])).to eq([{ 'id' => 'i1' }])
        expect(ForestAdminDatasourcePylon.logger).to have_received(:warn).with(/ignored the condition tree/)
      end

      it 'warns when a free-text search is supplied' do
        collection.list(nil, filter(search: 'boom'), %w[id])

        expect(ForestAdminDatasourcePylon.logger).to have_received(:warn).with(/ignored the search/)
      end

      it 'names both when a condition tree and a search are supplied' do
        tree = leaf('state', operators::EQUAL, 'closed')

        collection.list(nil, filter(condition_tree: tree, search: 'boom'), %w[id])

        expect(ForestAdminDatasourcePylon.logger)
          .to have_received(:warn).with(/ignored the condition tree and search/)
      end

      it 'stays quiet when nothing was dropped' do
        collection.list(nil, filter, %w[id])

        expect(ForestAdminDatasourcePylon.logger).not_to have_received(:warn)
      end

      it 'stays quiet on an empty search string' do
        collection.list(nil, filter(search: ''), %w[id])

        expect(ForestAdminDatasourcePylon.logger).not_to have_received(:warn)
      end
    end
  end
end
