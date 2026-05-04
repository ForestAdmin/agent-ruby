RSpec.describe ForestAdminDatasourceZendesk::Collections::Ticket do
  Filter      = ForestAdminDatasourceToolkit::Components::Query::Filter
  Page        = ForestAdminDatasourceToolkit::Components::Query::Page
  Sort        = ForestAdminDatasourceToolkit::Components::Query::Sort
  Aggregation = ForestAdminDatasourceToolkit::Components::Query::Aggregation
  Leaf        = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

  let(:client) { instance_double(ForestAdminDatasourceZendesk::Client) }
  let(:datasource) do
    instance_double(ForestAdminDatasourceZendesk::Datasource,
                    client: client, custom_field_mapping: {})
  end
  let(:collection) { described_class.new(datasource) }

  def zendesk_record(attrs)
    Struct.new(:attributes).new(attrs)
  end

  describe 'schema' do
    it 'declares the canonical ticket fields' do
      expect(collection.schema[:fields].keys).to include(
        'id', 'subject', 'description', 'status', 'priority', 'ticket_type',
        'requester_id', 'assignee_id', 'group_id', 'organization_id',
        'external_id', 'requester_email', 'tags', 'url', 'created_at', 'updated_at',
        'requester', 'assignee', 'organization', 'comments'
      )
    end

    it 'marks id as primary key' do
      expect(collection.schema[:fields]['id'].is_primary_key).to be(true)
    end

    it 'enables search and count' do
      expect(collection.is_searchable?).to be(true)
      expect(collection.is_countable?).to be(true)
    end

    it 'declares ManyToOne relations to User and Organization' do
      expect(collection.schema[:fields]['requester']).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
      expect(collection.schema[:fields]['organization']).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
    end

    it 'declares OneToMany comments' do
      expect(collection.schema[:fields]['comments']).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema)
    end
  end

  describe '#list' do
    let(:tickets) { [zendesk_record('id' => 1, 'subject' => 'a', 'requester_id' => 10)] }

    context 'when filtering by id (PK lookup)' do
      it 'short-circuits to find_ticket' do
        ticket = zendesk_record('id' => 215, 'subject' => 'show', 'requester_id' => 10)
        allow(client).to receive(:fetch_user_emails).with([10]).and_return(10 => 'x@y.com')
        expect(client).to receive(:find_ticket).with(215).and_return(ticket)
        expect(client).not_to receive(:search)

        filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 215))
        result = collection.list(nil, filter, %w[id subject requester_email])

        expect(result.first['id']).to eq(215)
        expect(result.first['requester_email']).to eq('x@y.com')
      end

      it 'fetches every id in an IN list' do
        expect(client).to receive(:find_ticket).with(1).and_return(zendesk_record('id' => 1, 'requester_id' => nil))
        expect(client).to receive(:find_ticket).with(2).and_return(zendesk_record('id' => 2, 'requester_id' => nil))
        allow(client).to receive(:fetch_user_emails).and_return({})

        filter = Filter.new(condition_tree: Leaf.new('id', 'in', [1, 2]))
        expect(collection.list(nil, filter, ['id']).map { |r| r['id'] }).to eq([1, 2])
      end

      it 'falls back to search when the id leaf uses an unsupported operator' do
        expect(client).to receive(:search).and_return([])
        expect(client).not_to receive(:find_ticket)

        filter = Filter.new(condition_tree: Leaf.new('id', 'greater_than', 100))
        collection.list(nil, filter, ['id'])
      end
    end

    context 'when filtering by other fields' do
      it 'translates the condition tree to a Zendesk Search query' do
        expect(client).to receive(:search) do |type, args|
          expect(type).to eq('ticket')
          expect(args[:query]).to eq('status:open')
          tickets
        end
        allow(client).to receive(:fetch_user_emails).and_return(10 => 'a@b.com')

        filter = Filter.new(condition_tree: Leaf.new('status', 'equal', 'open'))
        collection.list(nil, filter, ['id', 'subject'])
      end

      it 'merges filter.search into the query string' do
        expect(client).to receive(:search) do |_type, args|
          expect(args[:query]).to eq('status:open password reset')
          []
        end

        filter = Filter.new(
          condition_tree: Leaf.new('status', 'equal', 'open'),
          search: 'password reset'
        )
        collection.list(nil, filter, ['id'])
      end

      it 'forwards sort_by and sort_order' do
        expect(client).to receive(:search) do |_type, args|
          expect(args[:sort_by]).to eq('created_at')
          expect(args[:sort_order]).to eq('asc')
          []
        end

        filter = Filter.new(sort: Sort.new([{ field: 'created_at', ascending: true }]))
        collection.list(nil, filter, ['id'])
      end

      it 'sends sort_order=desc when sort.ascending is false' do
        expect(client).to receive(:search) do |_type, args|
          expect(args[:sort_order]).to eq('desc')
          []
        end

        filter = Filter.new(sort: Sort.new([{ field: 'updated_at', ascending: false }]))
        collection.list(nil, filter, ['id'])
      end

      it 'preserves ascending=false even when both symbol and string keys are present' do
        # Regression: `entry[:ascending] || entry['ascending']` would silently
        # flip a descending sort to ascending if both keys existed with
        # different values.
        expect(client).to receive(:search) do |_type, args|
          expect(args[:sort_order]).to eq('desc')
          []
        end

        filter = Filter.new(sort: Sort.new([{ field: 'updated_at', ascending: false,
                                              'ascending' => true }]))
        collection.list(nil, filter, ['id'])
      end

      it 'returns no sort_by when the field is not in Zendesk allow-list' do
        expect(client).to receive(:search) do |_type, args|
          expect(args[:sort_by]).to be_nil
          expect(args[:sort_order]).to be_nil
          []
        end

        filter = Filter.new(sort: Sort.new([{ field: 'subject', ascending: true }]))
        collection.list(nil, filter, ['id'])
      end

      it 'translates page offset/limit to Zendesk page/per_page' do
        expect(client).to receive(:search) do |_type, args|
          expect(args[:page]).to eq(3)
          expect(args[:per_page]).to eq(15)
          []
        end

        filter = Filter.new(page: Page.new(offset: 30, limit: 15))
        collection.list(nil, filter, ['id'])
      end

      it 'falls back to MAX_PER_PAGE when page.limit is nil' do
        expect(client).to receive(:search) do |_type, args|
          expect(args[:per_page]).to eq(ForestAdminDatasourceZendesk::Client::MAX_PER_PAGE)
          []
        end

        filter = Filter.new(page: Page.new(offset: 0, limit: nil))
        collection.list(nil, filter, ['id'])
      end
    end

    describe 'requester_email enrichment' do
      before do
        allow(client).to receive(:search).and_return([
                                                       zendesk_record('id' => 1, 'requester_id' => 10),
                                                       zendesk_record('id' => 2, 'requester_id' => 10),
                                                       zendesk_record('id' => 3, 'requester_id' => 20)
                                                     ])
      end

      it 'bulk-fetches emails when requester_email is in the projection' do
        expect(client).to receive(:fetch_user_emails)
          .with([10, 10, 20]).and_return(10 => 'a@b.com', 20 => 'c@d.com')

        result = collection.list(nil, Filter.new, ['id', 'requester_email'])
        expect(result.map { |r| r['requester_email'] }).to eq(%w[a@b.com a@b.com c@d.com])
      end

      it 'skips bulk fetch when requester_email is not requested' do
        expect(client).not_to receive(:fetch_user_emails)
        collection.list(nil, Filter.new, ['id', 'subject'])
      end

      it 'fetches by default when projection is nil' do
        expect(client).to receive(:fetch_user_emails).and_return({})
        collection.list(nil, Filter.new, nil)
      end
    end

    describe 'relation embedding (ManyToOne)' do
      let(:tickets) do
        [zendesk_record('id' => 1, 'requester_id' => 10, 'assignee_id' => 11, 'organization_id' => 50)]
      end

      before do
        allow(client).to receive(:search).and_return(tickets)
      end

      it 'embeds requester when requester:* is in projection' do
        allow(client).to receive(:fetch_user_emails).and_return({})
        expect(client).to receive(:fetch_users_by_ids)
          .with([10, 11])
          .and_return(10 => { 'id' => 10, 'email' => 'r@x.com', 'name' => 'R' })

        result = collection.list(nil, Filter.new, ['id', 'requester:id', 'requester:email'])
        expect(result.first['requester']).to include('id' => 10, 'email' => 'r@x.com')
      end

      it 'embeds organization when organization:* is in projection' do
        allow(client).to receive(:fetch_user_emails).and_return({})
        expect(client).to receive(:fetch_organizations_by_ids)
          .with([50])
          .and_return(50 => { 'id' => 50, 'name' => 'Acme' })

        result = collection.list(nil, Filter.new, ['id', 'organization:id', 'organization:name'])
        expect(result.first['organization']).to include('id' => 50, 'name' => 'Acme')
      end

      it 'skips relation fetches when only column projection is requested' do
        allow(client).to receive(:fetch_user_emails).and_return({})
        expect(client).not_to receive(:fetch_users_by_ids)
        expect(client).not_to receive(:fetch_organizations_by_ids)

        collection.list(nil, Filter.new, ['id', 'subject'])
      end

      it 'embeds only requester (no assignee) when only requester:* is in projection' do
        allow(client).to receive_messages(fetch_user_emails: {}, fetch_users_by_ids: { 10 => { 'id' => 10 } })

        result = collection.list(nil, Filter.new, ['id', 'requester:id']).first
        expect(result).to have_key('requester')
        expect(result).not_to have_key('assignee')
      end

      it 'fetches users but only embeds assignee when only assignee:* is requested' do
        allow(client).to receive_messages(fetch_user_emails: {}, fetch_users_by_ids: { 11 => { 'id' => 11 } })

        result = collection.list(nil, Filter.new, ['id', 'assignee:id']).first
        expect(result).to have_key('assignee')
        expect(result).not_to have_key('requester')
      end

      it 'leaves the relation hash nil when the foreign id is not resolvable' do
        allow(client).to receive_messages(search: [
                                            zendesk_record('id' => 9, 'requester_id' => 999,
                                                           'assignee_id' => nil, 'organization_id' => nil)
                                          ], fetch_user_emails: {}, fetch_users_by_ids: {})

        result = collection.list(nil, Filter.new, ['id', 'requester:id']).first
        expect(result['requester']).to be_nil
      end
    end

    describe 'projection edge cases' do
      it 'returns the full record when projection is nil' do
        allow(client).to receive_messages(search: [zendesk_record('id' => 1, 'requester_id' => nil)],
                                          fetch_user_emails: {})

        record = collection.list(nil, Filter.new, nil).first
        expect(record.keys).to include('id', 'subject', 'status')
      end

      it 'falls back to to_h when ticket lacks attributes' do
        plain_hash_ticket = { 'id' => 1, 'subject' => 'plain', 'requester_id' => nil }
        allow(client).to receive_messages(search: [plain_hash_ticket], fetch_user_emails: {})

        result = collection.list(nil, Filter.new, nil).first
        expect(result['subject']).to eq('plain')
      end
    end
  end

  describe 'timezone plumbing' do
    Caller = ForestAdminDatasourceToolkit::Components::Caller

    let(:paris_caller) do
      Caller.new(id: 1, email: 'x@x', first_name: 'X', last_name: 'Y',
                 tags: {}, team: 'Ops', rendering_id: 1, timezone: 'Europe/Paris',
                 permission_level: 'admin', role: 'Admin', request: {})
    end

    it 'feeds caller.timezone into the translator (Date filter shifts by TZ)' do
      expect(client).to receive(:search) do |_type, args|
        # Jan 15 in Paris is UTC+1 (no DST), so 00:00 local => 23:00 UTC previous day.
        expect(args[:query]).to eq('created_at>2026-01-14T23:00:00Z')
        []
      end
      allow(client).to receive(:fetch_user_emails).and_return({})

      filter = Filter.new(condition_tree: Leaf.new('created_at', 'after', Date.new(2026, 1, 15)))
      collection.list(paris_caller, filter, ['id'])
    end

    it 'falls back to UTC when caller is nil' do
      expect(client).to receive(:search) do |_type, args|
        expect(args[:query]).to eq('created_at>2026-04-27T00:00:00Z')
        []
      end
      allow(client).to receive(:fetch_user_emails).and_return({})

      filter = Filter.new(condition_tree: Leaf.new('created_at', 'after', Date.new(2026, 4, 27)))
      collection.list(nil, filter, ['id'])
    end

    it 'falls back to UTC when caller.timezone is blank' do
      blank_tz_caller = Caller.new(id: 1, email: 'x@x', first_name: 'X', last_name: 'Y',
                                   tags: {}, team: 'Ops', rendering_id: 1, timezone: '',
                                   permission_level: 'admin', role: 'Admin', request: {})
      expect(client).to receive(:search) do |_type, args|
        expect(args[:query]).to eq('created_at>2026-04-27T00:00:00Z')
        []
      end
      allow(client).to receive(:fetch_user_emails).and_return({})

      filter = Filter.new(condition_tree: Leaf.new('created_at', 'after', Date.new(2026, 4, 27)))
      collection.list(blank_tz_caller, filter, ['id'])
    end
  end

  describe '#aggregate' do
    it 'returns the count under string keys' do
      expect(client).to receive(:count).with('ticket', query: 'status:open').and_return(7)

      result = collection.aggregate(nil,
                                    Filter.new(condition_tree: Leaf.new('status', 'equal', 'open')),
                                    Aggregation.new(operation: 'Count'))

      expect(result).to eq([{ 'value' => 7, 'group' => {} }])
    end

    it 'raises for unsupported aggregations' do
      expect do
        collection.aggregate(nil, Filter.new, Aggregation.new(operation: 'Sum', field: 'priority'))
      end.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException)
    end
  end

  describe 'custom fields integration' do
    let(:cf_schema) do
      ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(column_type: 'String',
                                                             filter_operators: [], is_read_only: true)
    end
    let(:custom_fields) do
      [{ column_name: 'custom_360001', zendesk_id: 360_001, zendesk_key: nil, schema: cf_schema }]
    end
    let(:collection) { described_class.new(datasource, custom_fields: custom_fields) }

    it 'adds the custom field to the schema' do
      expect(collection.schema[:fields]).to have_key('custom_360001')
    end

    it 'serializes the custom field value from ticket.custom_fields array' do
      ticket = zendesk_record('id' => 1, 'requester_id' => nil, 'custom_fields' => [
                                { 'id' => 360_001, 'value' => 'gold' },
                                { 'id' => 999_999, 'value' => 'ignored' }
                              ])
      allow(client).to receive_messages(search: [ticket], fetch_user_emails: {})

      result = collection.list(nil, Filter.new, nil).first
      expect(result['custom_360001']).to eq('gold')
    end
  end

  describe '#create' do
    it 'POSTs the payload, renames ticket_type -> type, and lifts description into the initial comment' do
      expect(client).to receive(:create_ticket) do |payload|
        expect(payload).to include('subject' => 'Hi', 'type' => 'incident',
                                   'comment' => { 'body' => 'longer body' })
        expect(payload).not_to have_key('ticket_type')
        expect(payload).not_to have_key('description')
        { 'id' => 42, 'subject' => 'Hi', 'type' => 'incident' }
      end

      result = collection.create(nil,
                                 'subject' => 'Hi',
                                 'ticket_type' => 'incident',
                                 'description' => 'longer body')
      expect(result['id']).to eq(42)
    end

    it 'omits the comment when description is blank' do
      expect(client).to receive(:create_ticket) do |payload|
        expect(payload).not_to have_key('comment')
        { 'id' => 1 }
      end
      collection.create(nil, 'subject' => 'Hi')
    end

    it 'strips read-only and PK fields from the payload' do
      expect(client).to receive(:create_ticket) do |payload|
        expect(payload.keys).not_to include('id', 'requester_email', 'url',
                                            'created_at', 'updated_at')
        { 'id' => 1 }
      end
      collection.create(nil, 'id' => 99, 'requester_email' => 'a@b.com',
                             'url' => 'x', 'created_at' => 't', 'updated_at' => 't',
                             'subject' => 'S')
    end

    context 'with custom fields' do
      let(:cf_schema) do
        ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
          column_type: 'String', filter_operators: [], is_read_only: false
        )
      end
      let(:custom_fields) do
        [{ column_name: 'custom_360001', zendesk_id: 360_001, zendesk_key: nil, schema: cf_schema }]
      end
      let(:collection) { described_class.new(datasource, custom_fields: custom_fields) }

      it 'folds custom_<id> columns into the custom_fields array' do
        expect(client).to receive(:create_ticket) do |payload|
          expect(payload['custom_fields']).to eq([{ 'id' => 360_001, 'value' => 'gold' }])
          expect(payload).not_to have_key('custom_360001')
          { 'id' => 1 }
        end
        collection.create(nil, 'subject' => 'X', 'custom_360001' => 'gold')
      end
    end
  end

  describe '#update' do
    it 'updates every id resolved from the filter (PK lookup short-circuit)' do
      allow(client).to receive(:fetch_user_emails).and_return({})
      ticket = zendesk_record('id' => 12, 'subject' => 'A', 'requester_id' => nil)
      allow(client).to receive(:find_ticket).with(12).and_return(ticket)

      expect(client).to receive(:update_ticket).with(12, hash_including('status' => 'solved'))

      filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 12))
      collection.update(nil, filter, 'status' => 'solved')
    end

    it 'updates each id when the filter resolves to several' do
      allow(client).to receive(:fetch_user_emails).and_return({})
      [1, 2].each do |id|
        allow(client).to receive(:find_ticket).with(id).and_return(zendesk_record('id' => id, 'requester_id' => nil))
      end

      expect(client).to receive(:update_ticket).with(1, hash_including('priority' => 'high'))
      expect(client).to receive(:update_ticket).with(2, hash_including('priority' => 'high'))

      filter = Filter.new(condition_tree: Leaf.new('id', 'in', [1, 2]))
      collection.update(nil, filter, 'priority' => 'high')
    end

    it 'silently drops description on update (no comment write path)' do
      allow(client).to receive(:fetch_user_emails).and_return({})
      allow(client).to receive(:find_ticket).with(7).and_return(zendesk_record('id' => 7, 'requester_id' => nil))

      expect(client).to receive(:update_ticket) do |id, payload|
        expect(id).to eq(7)
        expect(payload).not_to have_key('comment')
        expect(payload).not_to have_key('description')
      end

      filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 7))
      collection.update(nil, filter, 'description' => 'should be ignored')
    end
  end

  describe '#delete' do
    it 'deletes each id resolved from the filter' do
      allow(client).to receive(:fetch_user_emails).and_return({})
      [1, 2].each do |id|
        allow(client).to receive(:find_ticket).with(id).and_return(zendesk_record('id' => id, 'requester_id' => nil))
      end

      expect(client).to receive(:delete_ticket).with(1)
      expect(client).to receive(:delete_ticket).with(2)

      filter = Filter.new(condition_tree: Leaf.new('id', 'in', [1, 2]))
      collection.delete(nil, filter)
    end
  end

  describe 'schema writability' do
    it 'marks user-editable fields as writable' do
      fields = collection.schema[:fields]
      expect(fields['subject'].is_read_only).to be(false)
      expect(fields['status'].is_read_only).to be(false)
      expect(fields['priority'].is_read_only).to be(false)
      expect(fields['requester_id'].is_read_only).to be(false)
    end

    it 'keeps server-managed fields read-only' do
      fields = collection.schema[:fields]
      expect(fields['id'].is_read_only).to be(true)
      expect(fields['url'].is_read_only).to be(true)
      expect(fields['created_at'].is_read_only).to be(true)
      expect(fields['requester_email'].is_read_only).to be(true)
    end
  end
end
