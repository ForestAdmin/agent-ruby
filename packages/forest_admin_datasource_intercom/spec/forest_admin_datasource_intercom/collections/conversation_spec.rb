module ForestAdminDatasourceIntercom
  RSpec.describe Collections::Conversation do
    subject(:collection) { datasource.get_collection('IntercomConversation') }

    let(:datasource) { Datasource.new(access_token: 's3cr3t', rate_limiter: nil) }
    let(:base) { datasource.configuration.url }
    let(:operators) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators }

    def filter(condition_tree: nil, page: nil, sort: nil)
      ForestAdminDatasourceToolkit::Components::Query::Filter.new(condition_tree: condition_tree, page: page,
                                                                  sort: sort)
    end

    def leaf(field, operator, value = nil)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
        .new(field, operator, value)
    end

    def branch(aggregator, *conditions)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch
        .new(aggregator, conditions)
    end

    def json(payload, status = 200)
      { status: status, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end

    # The columns alone: a relation carries neither operators nor an order, and
    # what it may be filtered through is asserted on its own below.
    def columns
      collection.fields.select { |_, field| field.type == 'Column' }
    end

    # Hand-written from the OpenAPI 2.16 spec, never captured from a workspace:
    # a conversation body is personal data.
    def conversation(id, overrides = {})
      {
        'type' => 'conversation', 'id' => id, 'title' => "Facture #{id}", 'state' => 'closed',
        'priority' => 'priority', 'open' => false, 'read' => true,
        'created_at' => 1_700_000_000, 'updated_at' => 1_700_003_600,
        'waiting_since' => nil, 'snoozed_until' => nil,
        'admin_assignee_id' => 493_881, 'team_assignee_id' => 814_865,
        'company' => { 'type' => 'company', 'id' => '696dd52099f73812610d9c7b', 'name' => 'Acme' },
        'contacts' => { 'type' => 'contact.list',
                        'contacts' => [{ 'type' => 'contact', 'id' => 'c1' }, { 'type' => 'contact', 'id' => 'c2' }] },
        'tags' => { 'type' => 'tag.list', 'tags' => [{ 'id' => 't1', 'name' => 'billing' }] },
        'ai_agent_participated' => true,
        'source' => { 'type' => 'conversation', 'id' => 's1', 'delivered_as' => 'customer_initiated',
                      'subject' => 'Ma facture', 'body' => 'Bonjour, ou est ma facture ?',
                      'author' => { 'type' => 'user', 'id' => 'c1', 'name' => 'Camille',
                                    'email' => 'camille@acme.test' },
                      'attachments' => [] },
        'statistics' => { 'type' => 'conversation_statistics', 'first_close_at' => 1_700_002_000,
                          'last_close_at' => 1_700_003_000, 'last_closed_by_id' => '493881',
                          'first_contact_reply_at' => 1_700_000_050, 'last_contact_reply_at' => 1_700_001_000,
                          'last_admin_reply_at' => 1_700_002_500, 'count_reopens' => 1,
                          'count_conversation_parts' => 4 }
      }.merge(overrides)
    end

    def parts(*entries)
      { 'conversation_parts' => { 'type' => 'conversation_part.list', 'conversation_parts' => entries } }
    end

    def part(part_type, overrides = {})
      { 'type' => 'conversation_part', 'id' => 'p1', 'part_type' => part_type, 'body' => 'Je regarde.',
        'created_at' => 1_700_002_500, 'redacted' => false, 'attachments' => [],
        'author' => { 'type' => 'admin', 'id' => '493881', 'name' => 'Alice',
                      'email' => 'alice@acme.test' } }.merge(overrides)
    end

    # Intercom puts the records under `conversations`, not under the `data`
    # envelope -- measured on `/tickets/search`, and the listings follow the same
    # habit.
    def stub_list(*records, next_cursor: nil, total: nil, query: hash_including({}))
      body = { 'type' => 'conversation.list', 'conversations' => records,
               'total_count' => total || records.size, 'pages' => { 'type' => 'pages', 'page' => 1 } }
      body['pages']['next'] = { 'starting_after' => next_cursor } if next_cursor

      stub_request(:get, "#{base}/conversations").with(query: query).to_return(json(body))
    end

    def stub_search(*records, total: nil, next_cursor: nil)
      body = { 'type' => 'conversation.list', 'conversations' => records,
               'total_count' => total || records.size, 'pages' => { 'type' => 'pages', 'page' => 1 } }
      body['pages']['next'] = { 'starting_after' => next_cursor } if next_cursor

      stub_request(:post, "#{base}/conversations/search").with(query: hash_including({})).to_return(json(body))
    end

    def stub_record(id, payload, status = 200)
      stub_request(:get, "#{base}/conversations/#{id}").with(query: hash_including({})).to_return(json(payload, status))
    end

    def ids(rows)
      rows.map { |row| row['id'] }
    end

    describe 'schema' do
      it 'is named IntercomConversation' do
        expect(collection.name).to eq('IntercomConversation')
      end

      # Neither search endpoint takes a sort, and Intercom ignores the one it is
      # sent without a word, so no column of this tier may advertise one.
      it 'declares every column unsortable' do
        expect(columns.values.map(&:is_sortable).uniq).to eq([false])
      end

      # Derived from the measured table, never written by hand: a column
      # advertises exactly what the search endpoint answers on it.
      it 'advertises the filters the search endpoint answers, and only those' do
        expect(collection.fields['state'].filter_operators).to eq(%w[equal not_equal])
        expect(collection.fields['created_at'].filter_operators).to eq(%w[greater_than less_than])
        expect(collection.fields['source_body'].filter_operators).to eq(%w[contains i_contains not_contains])
      end

      # A column the table does not carry advertises nothing, which is how a
      # refusal is spelled in a schema: the tag names, the company, the timeline
      # and the contact identity are all read from somewhere the endpoint does
      # not filter.
      it 'advertises no filter on a column the endpoint does not filter' do
        %w[tag_names company_name contact_email timeline contact_ids].each do |column|
          expect(collection.fields[column].filter_operators).to be_empty, "#{column} advertises a filter"
        end
      end

      it 'is searchable, Intercom matching text on the body of the first message' do
        expect(collection.is_searchable?).to be(true)
      end

      # The record detail is `id equals X`, answered by the record endpoint
      # rather than by a filter.
      it 'answers the primary key with equal and in' do
        expect(collection.fields['id'].filter_operators).to eq(%w[equal in])
      end

      it 'is countable, since total_count is exact' do
        expect(collection.is_countable?).to be(true)
      end

      # No aggregate endpoint, so no group-by may be offered.
      it 'declares no column groupable' do
        expect(columns.values.map(&:is_groupable).uniq).to eq([false])
      end

      # This lot writes nothing: an editable column would offer a Save that
      # reaches an `update` the collection does not implement.
      it 'declares every column read-only' do
        expect(collection.fields.values.map(&:is_read_only).uniq).to eq([true])
      end
    end

    # All three targets are read whole in one request, and
    # `/conversations/search` takes a filter on each of the three keys -- so
    # these relations can be read, navigated and filtered through alike, unlike
    # the state of a ticket.
    describe 'the relations to the reference collections' do
      it 'points every id at the collection that reads it' do
        expect(collection.fields['admin_assignee'])
          .to have_attributes(type: 'ManyToOne', foreign_collection: 'IntercomAdmin',
                              foreign_key: 'admin_assignee_id', foreign_key_target: 'id', is_read_only: true)
        expect(collection.fields['team_assignee'])
          .to have_attributes(foreign_collection: 'IntercomTeam', foreign_key: 'team_assignee_id')
        expect(collection.fields['closed_by'])
          .to have_attributes(foreign_collection: 'IntercomAdmin', foreign_key: 'closed_by_id')
      end

      # The account is on the payload as a whole object, so the name is already a
      # column; the Companies collection arrives with lot 4, and a relation whose
      # target is missing is a schema the agent refuses to boot on.
      it 'declares no relation towards the account' do
        expect(collection.fields.keys).not_to include('company')
      end

      it 'nests the teammate who closed it, reading the teammates once for the page' do
        stub_list(conversation('1'), conversation('2'))
        stub_request(:get, "#{base}/admins")
          .to_return(json('type' => 'admin.list', 'admins' => [{ 'id' => '493881', 'name' => 'Alice' }]))

        rows = collection.list(nil, filter, ['id', 'closed_by:name'])

        expect(rows).to eq([{ 'id' => '1', 'closed_by' => { 'name' => 'Alice', 'id' => '493881' } },
                            { 'id' => '2', 'closed_by' => { 'name' => 'Alice', 'id' => '493881' } }])
        expect(WebMock).to have_requested(:get, "#{base}/admins").once
      end

      it 'filters on the foreign key the target resolved to' do
        stub_request(:get, "#{base}/admins")
          .to_return(json('type' => 'admin.list', 'admins' => [{ 'id' => '493881', 'name' => 'Alice' }]))
        stub_search(conversation('1'))

        collection.list(nil, filter(condition_tree: leaf('admin_assignee:name', operators::EQUAL, 'Alice')), %w[id])

        expect(WebMock).to have_requested(:post, "#{base}/conversations/search")
          .with(query: hash_including({}),
                body: hash_including('query' => { 'field' => 'admin_assignee_id', 'operator' => '=',
                                                  'value' => '493881' }))
      end
    end

    describe '#list' do
      it 'reads the listing endpoint as plain text and pages by cursor' do
        stub_list(conversation('1'))

        collection.list(nil, filter, nil)

        expect(WebMock).to have_requested(:get, "#{base}/conversations")
          .with(query: hash_including('display_as' => 'plaintext'))
      end

      it 'flattens the payload into the row the schema declares' do
        stub_list(conversation('1'))

        row = collection.list(nil, filter, nil).first

        expect(row).to include('id' => '1', 'title' => 'Facture 1', 'state' => 'closed', 'open' => false,
                               'company_id' => '696dd52099f73812610d9c7b', 'company_name' => 'Acme',
                               'admin_assignee_id' => '493881', 'team_assignee_id' => '814865',
                               'tag_names' => %w[billing], 'ai_agent_participated' => true)
      end

      # Epoch seconds are what Intercom sends; a Date column and a date filter
      # both read ISO8601, and UTC is where Intercom truncates.
      it 'reads the dates as ISO8601 in UTC' do
        row = (stub_list(conversation('1')) && collection.list(nil, filter, nil)).first

        expect(row['created_at']).to eq('2023-11-14T22:13:20Z')
      end

      it 'flattens the lifecycle Intercom keeps in statistics' do
        stub_list(conversation('1'))

        expect(collection.list(nil, filter, nil).first)
          .to include('closed_at' => '2023-11-14T23:03:20Z', 'closed_by_id' => '493881',
                      'last_admin_reply_at' => '2023-11-14T22:55:00Z', 'reopen_count' => 1, 'part_count' => 4)
      end

      # A conversation Intercom has computed nothing for yet answers a null
      # statistics; the columns then read as absent rather than as zero.
      it 'reads a missing statistics block as absent, not as zero' do
        stub_list(conversation('1', 'statistics' => nil))

        expect(collection.list(nil, filter, nil).first)
          .to include('closed_at' => nil, 'reopen_count' => nil)
      end

      # A group conversation has several contacts: the row names how many rather
      # than presenting one of them as the one.
      it 'carries the contact ids and their count' do
        stub_list(conversation('1'))

        expect(collection.list(nil, filter, nil).first)
          .to include('contact_ids' => %w[c1 c2], 'contact_count' => 2)
      end

      it 'narrows the row to the projection' do
        stub_list(conversation('1'))

        expect(collection.list(nil, filter, %w[id state])).to eq([{ 'id' => '1', 'state' => 'closed' }])
      end

      it 'walks the cursor until the window is covered' do
        first = { 'conversations' => [conversation('1'), conversation('2')],
                  'pages' => { 'next' => { 'starting_after' => 'c2' } } }
        stub_request(:get, "#{base}/conversations").with(query: hash_including('per_page' => '3'))
                                                   .to_return(json(first))
        stub_request(:get, "#{base}/conversations").with(query: hash_including('starting_after' => 'c2'))
                                                   .to_return(json('conversations' => [conversation('3')]))

        page = ForestAdminDatasourceToolkit::Components::Query::Page.new(offset: 2, limit: 1)

        expect(ids(collection.list(nil, filter(page: page), %w[id]))).to eq(%w[3])
      end
    end

    describe '#list of one record' do
      # What a record detail is. It goes to the record endpoint rather than to
      # the listing, which is also what brings the parts along.
      it 'reads id equals X through the record endpoint' do
        stub_record('1', conversation('1'))

        expect(ids(collection.list(nil, filter(condition_tree: leaf('id', operators::EQUAL, '1')), %w[id])))
          .to eq(%w[1])
      end

      # A stale link, or a record outside the token's scope: no record, not a
      # failed page.
      it 'reads a 404 as no record' do
        stub_record('gone', { 'errors' => [{ 'code' => 'not_found' }] }, 404)

        expect(collection.list(nil, filter(condition_tree: leaf('id', operators::EQUAL, 'gone')), %w[id])).to eq([])
      end

      it 'still raises on a failure that is not a missing record' do
        stub_record('1', { 'errors' => [{ 'code' => 'forbidden' }] }, 403)

        expect { collection.list(nil, filter(condition_tree: leaf('id', operators::EQUAL, '1')), %w[id]) }
          .to raise_error(APIError)
      end

      # A permission scope turns the record detail into `id equals X and <the
      # scope>`, which the record endpoint cannot answer: the ids name a wider
      # set than the scope does, and reading them alone would serve a record the
      # scope excludes. It goes to the search, where the key is a field like any
      # other -- and the whole condition travels, or none of it does.
      it 'reads the key through the search once a scope is filtered alongside it' do
        search = stub_search(conversation('1'))
        tree = branch('And', leaf('id', operators::EQUAL, '1'), leaf('state', operators::EQUAL, 'closed'))

        expect(ids(collection.list(nil, filter(condition_tree: tree), %w[id]))).to eq(%w[1])
        expect(search).to have_been_requested
      end

      it 'sends the scope and the key as the one query, neither dropped' do
        stub_search(conversation('1'))
        tree = branch('And', leaf('id', operators::IN, %w[1 2]), leaf('open', operators::EQUAL, false))

        collection.list(nil, filter(condition_tree: tree), %w[id])

        expected = { 'operator' => 'AND',
                     'value' => [{ 'field' => 'id', 'operator' => 'IN', 'value' => %w[1 2] },
                                 { 'field' => 'open', 'operator' => '=', 'value' => false }] }

        expect(a_request(:post, "#{base}/conversations/search")
                 .with(query: hash_including({}), body: hash_including('query' => expected))).to have_been_made
      end
    end

    describe '#list of several records by id' do
      # What a pointing collection asks for when it reads related records in
      # bulk. Intercom has no "read these records" endpoint, so it is one
      # request per id -- and therefore bounded.
      it 'reads each id through the record endpoint' do
        %w[1 2].each do |id|
          stub_record(id, conversation(id))
        end

        rows = collection.list(nil, filter(condition_tree: leaf('id', operators::IN, %w[1 2])), %w[id])

        expect(ids(rows)).to eq(%w[1 2])
      end

      # A pointing collection pages through the records it named, and every page
      # must name different ones: cut out of the records instead of out of the
      # ids, the window would render the same rows on page 1 and page 2 -- and
      # a page past the cap would come back empty, its ids having been dropped
      # by the truncation before the window was applied.
      it 'reads only the ids the page window names' do
        stub_record('2', conversation('2'))
        page = ForestAdminDatasourceToolkit::Components::Query::Page.new(offset: 1, limit: 1)
        tree = leaf('id', operators::IN, %w[1 2 3])

        expect(ids(collection.list(nil, filter(condition_tree: tree, page: page), %w[id]))).to eq(%w[2])
      end

      it 'reads the first of too many and says the result is truncated' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        asked = (1..(Collections::CursorCollection::MAX_ID_READS + 3)).map(&:to_s)
        stub_request(:get, %r{/conversations/\d+}).to_return(json(conversation('1')))

        rows = collection.list(nil, filter(condition_tree: leaf('id', operators::IN, asked)), %w[id])

        expect(rows.size).to eq(Collections::CursorCollection::MAX_ID_READS)
        expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/read the first 25/)
      end
    end

    describe 'a filter Intercom answers' do
      # A condition switches the read from the listing to the search endpoint,
      # which is the only one that takes a filter.
      it 'searches instead of listing, with the query the translator wrote' do
        search = stub_search
        tree = leaf('state', operators::EQUAL, 'open')

        collection.list(nil, filter(condition_tree: tree), %w[id])

        expect(search.with(body: hash_including('query' => { 'field' => 'state', 'operator' => '=',
                                                             'value' => 'open' }))).to have_been_made
      end

      # The bodies are HTML written by end customers (R10), and a filtered read
      # must not come back as markup where an unfiltered one comes back as text.
      it 'asks the search for plain text too' do
        search = stub_search

        collection.list(nil, filter(condition_tree: leaf('open', operators::EQUAL, true)), %w[id])

        expect(search.with(query: hash_including('display_as' => 'plaintext'))).to have_been_made
      end

      it 'walks the search cursor for the window a list view asked for' do
        stub_request(:post, "#{base}/conversations/search")
          .with(query: hash_including({}))
          .to_return(json({ 'conversations' => [conversation('1'), conversation('2')],
                            'pages' => { 'next' => { 'starting_after' => 'c2' } } }))
        stub_request(:post, "#{base}/conversations/search")
          .with(query: hash_including({}),
                body: hash_including('pagination' => hash_including('starting_after' => 'c2')))
          .to_return(json('conversations' => [conversation('3')]))
        page = ForestAdminDatasourceToolkit::Components::Query::Page.new(offset: 2, limit: 1)

        rows = collection.list(nil, filter(condition_tree: leaf('open', operators::EQUAL, true), page: page), %w[id])

        expect(ids(rows)).to eq(%w[3])
      end

      # Per word rather than as a substring, which the README says out loud.
      it 'answers a free-text search on the body of the message that opened the conversation' do
        search = stub_search
        searched = ForestAdminDatasourceToolkit::Components::Query::Filter.new(search: ' facture ')

        collection.list(nil, searched, %w[id])

        expect(search.with(body: hash_including('query' => { 'field' => 'source.body', 'operator' => '~',
                                                             'value' => 'facture' }))).to have_been_made
      end

      # Written as one tree rather than added to the translated query: the
      # nesting Intercom allows is then checked over the whole of it.
      it 'ands a free-text search with the condition it came with' do
        search = stub_search
        searched = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
          search: 'facture', condition_tree: leaf('open', operators::EQUAL, true)
        )

        collection.list(nil, searched, %w[id])

        expect(search.with { |request| JSON.parse(request.body)['query']['operator'] == 'AND' }).to have_been_made
      end

      # The date bounds Intercom answers are the ones the day rule moved, which
      # is what makes an interval answer the day it names.
      it 'sends a date bound on the UTC day boundary that answers the day asked for' do
        search = stub_search
        tree = leaf('created_at', operators::GREATER_THAN, '2026-09-01T08:30:00Z')

        collection.list(nil, filter(condition_tree: tree), %w[id])

        expect(search.with(body: hash_including('query' => hash_including('value' => Time.utc(2026, 8,
                                                                                              31).to_i))))
          .to have_been_made
      end
    end

    describe 'a filter it cannot honour' do
      # A condition dropped on the way to Intercom comes back as an unfiltered
      # page that looks filtered, which is the one answer this datasource must
      # not give.
      it 'refuses a condition on a column the endpoint does not filter' do
        expect { collection.list(nil, filter(condition_tree: leaf('tag_names', operators::EQUAL, 'billing')), %w[id]) }
          .to raise_error(UnsupportedOperatorError, /cannot filter "tag_names"/)
      end

      it 'refuses an operator the endpoint does not answer on that column' do
        expect { collection.list(nil, filter(condition_tree: leaf('state', operators::CONTAINS, 'op')), %w[id]) }
          .to raise_error(UnsupportedOperatorError, /answers equal, not_equal on "state"/)
      end

      it 'makes no request at all when it refuses' do
        expect { collection.list(nil, filter(condition_tree: leaf('tag_names', operators::EQUAL, 'x')), %w[id]) }
          .to raise_error(UnsupportedOperatorError)
        expect(a_request(:post, "#{base}/conversations/search")).not_to have_been_made
      end
    end

    describe 'a sort Intercom ignores' do
      before { allow(ForestAdminDatasourceIntercom.logger).to receive(:warn) }

      # Measured: a sort sent to this endpoint raises nothing and changes
      # nothing, so an order the operator asked for and did not get can only be
      # reported here.
      it 'reports the order it did not get' do
        stub_list(conversation('1'))
        sort = ForestAdminDatasourceToolkit::Components::Query::Sort.new([{ field: 'created_at', ascending: false }])

        collection.list(nil, filter(sort: sort), %w[id])

        expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/ignores a sort/)
      end

      # `?sort=-id` is an order the operator asked for, not the ascending default
      # the agent injects when a request names none.
      it 'reports an explicit descending order on the primary key' do
        stub_list(conversation('1'))
        sort = ForestAdminDatasourceToolkit::Components::Query::Sort.new([{ field: 'id', ascending: false }])

        collection.list(nil, filter(sort: sort), %w[id])

        expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/ignores a sort/)
      end

      it 'stays quiet on the primary-key order the agent injects by default' do
        stub_list(conversation('1'))
        sort = ForestAdminDatasourceToolkit::Components::Query::Sort.new([{ field: 'id', ascending: true }])

        collection.list(nil, filter(sort: sort), %w[id])

        expect(ForestAdminDatasourceIntercom.logger).not_to have_received(:warn)
      end
    end

    describe '#aggregate' do
      def aggregation(operation, field: nil, groups: [])
        ForestAdminDatasourceToolkit::Components::Query::Aggregation.new(operation: operation, field: field,
                                                                         groups: groups)
      end

      # One request, and exact on the whole collection rather than on the page
      # the walk happened to read.
      it 'counts through total_count' do
        stub_list(conversation('1'), total: 81_142, query: hash_including('per_page' => '1'))

        expect(collection.aggregate(nil, filter, aggregation('Count')))
          .to eq([{ 'group' => {}, 'value' => 81_142 }])
      end

      it 'counts the records an id lookup found' do
        stub_record('1', conversation('1'))

        expect(collection.aggregate(nil, filter(condition_tree: leaf('id', operators::EQUAL, '1')),
                                    aggregation('Count')).first['value']).to eq(1)
      end

      # Grouping over the pages a walk collected would look exact while
      # answering a fraction.
      it 'refuses a group-by' do
        expect { collection.aggregate(nil, filter, aggregation('Count', groups: [{ field: 'state' }])) }
          .to raise_error(UnsupportedOperatorError, /can only be counted/)
      end

      it 'refuses a sum' do
        expect { collection.aggregate(nil, filter, aggregation('Sum', field: 'reopen_count')) }
          .to raise_error(UnsupportedOperatorError, /can only be counted/)
      end

      # `total_count` is exact on a search too, so a filtered count is one
      # request over the whole filtered set rather than over a page of it.
      it 'counts a filtered collection through the search, in one request' do
        stub_search(total: 1_234)

        value = collection.aggregate(nil, filter(condition_tree: leaf('state', operators::EQUAL, 'open')),
                                     aggregation('Count')).first['value']

        expect(value).to eq(1_234)
      end

      it 'refuses to count what it refuses to list' do
        expect do
          collection.aggregate(nil, filter(condition_tree: leaf('tag_names', operators::EQUAL, 'billing')),
                               aggregation('Count'))
        end.to raise_error(UnsupportedOperatorError, /cannot filter "tag_names"/)
      end

      # Counting the pages a walk collected would answer a fraction as if it
      # were the whole, so a listing with no total_count is a listing this
      # cannot count.
      it 'refuses to count a listing Intercom answered without a total_count' do
        stub_request(:get, "#{base}/conversations").with(query: hash_including({}))
                                                   .to_return(json('conversations' => [],
                                                                   'pages' => { 'type' => 'pages' }))

        expect { collection.aggregate(nil, filter, aggregation('Count')) }
          .to raise_error(UnsupportedOperatorError, /without a total_count/)
      end
    end

    describe 'the contact identity' do
      before do
        stub_list(conversation('1'))
        stub_request(:post, "#{base}/contacts/search")
          .to_return(json('type' => 'list',
                          'data' => [{ 'id' => 'c1', 'name' => 'Camille', 'email' => 'camille@acme.test' }]))
      end

      # Denormalized rather than declared as a relation: the Contacts collection
      # arrives in lot 4, and a relation whose target is missing is a schema the
      # agent refuses to boot on.
      it 'reads the identity of the page in one request and puts it on the row' do
        row = collection.list(nil, filter, %w[id contact_name contact_email]).first

        expect(row).to include('contact_name' => 'Camille', 'contact_email' => 'camille@acme.test')
        expect(WebMock).to have_requested(:post, "#{base}/contacts/search").once
      end

      it 'asks for the contacts of the page by id' do
        collection.list(nil, filter, %w[id contact_name])

        expect(WebMock).to have_requested(:post, "#{base}/contacts/search")
          .with(body: hash_including('query' => { 'field' => 'id', 'operator' => 'IN', 'value' => %w[c1] }))
      end

      # A page that never asked for the identity must not pay for it.
      it 'reads nothing when the projection does not name it' do
        collection.list(nil, filter, %w[id state])

        expect(WebMock).not_to have_requested(:post, "#{base}/contacts/search")
      end

      # An identity that could not be read is not a page that could not be
      # served: it costs the two columns.
      it 'degrades to empty columns when the read fails' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_request(:post, "#{base}/contacts/search").to_return(json({ 'errors' => [] }, 403))

        row = collection.list(nil, filter, %w[id contact_name]).first

        expect(row['contact_name']).to be_nil
        expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/could not read the contacts/)
      end
    end

    describe 'the timeline' do
      let(:conversation_with_parts) do
        conversation('1').merge(parts(part('assignment', 'id' => 'p1', 'body' => nil, 'created_at' => 1_700_000_100),
                                      part('comment', 'id' => 'p2', 'created_at' => 1_700_002_500)))
      end

      # The message that opened the conversation lives in `source`, not in the
      # parts: a timeline built from the parts alone loses what the customer
      # actually asked.
      it 'opens on the source message' do
        stub_record('1', conversation_with_parts)

        timeline = collection.list(nil, filter(condition_tree: leaf('id', operators::EQUAL, '1')),
                                   %w[id timeline]).first['timeline']

        expect(timeline.first).to include('part_type' => 'conversation_started',
                                          'body' => 'Bonjour, ou est ma facture ?',
                                          'author_name' => 'Camille', 'created_at' => '2023-11-14T22:13:20Z')
      end

      # An assignment, a note and a reply are not the same event; a thread that
      # flattens them reads as a conversation that never happened that way.
      it 'keeps the part type of every entry' do
        stub_record('1', conversation_with_parts)

        timeline = collection.list(nil, filter(condition_tree: leaf('id', operators::EQUAL, '1')),
                                   %w[timeline]).first['timeline']

        expect(timeline.map { |entry| entry['part_type'] }).to eq(%w[conversation_started assignment comment])
      end

      it 'costs no request on a record read, the parts riding along with it' do
        stub_record('1', conversation_with_parts)

        collection.list(nil, filter(condition_tree: leaf('id', operators::EQUAL, '1')), %w[timeline])

        expect(WebMock).to have_requested(:get, "#{base}/conversations/1")
          .with(query: hash_including({})).once
      end

      # Intercom returns the parts only when retrieving one conversation, so a
      # list view pays a request per row.
      it 'reads the record when a listed row has no parts' do
        stub_list(conversation('1'))
        stub_record('1', conversation_with_parts)

        rows = collection.list(nil, filter, %w[id timeline])

        expect(rows.first['timeline'].size).to eq(3)
      end

      it 'reads nothing when the projection does not name it' do
        stub_list(conversation('1'))

        collection.list(nil, filter, %w[id state])

        expect(WebMock).not_to have_requested(:get, "#{base}/conversations/1").with(query: hash_including({}))
      end

      # A conversation deleted between the page and the read of its timeline:
      # the row keeps a nil timeline rather than failing the whole page.
      it 'leaves the timeline unread when the record has gone' do
        stub_list(conversation('1'))
        stub_record('1', { 'errors' => [{ 'code' => 'not_found' }] }, 404)

        expect(collection.list(nil, filter, %w[id timeline]).first['timeline']).to be_nil
      end

      it 'still raises when the timeline read fails for another reason' do
        stub_list(conversation('1'))
        stub_record('1', { 'errors' => [{ 'code' => 'forbidden' }] }, 403)

        expect { collection.list(nil, filter, %w[id timeline]) }.to raise_error(APIError)
      end

      # Rows past the cap keep a nil timeline -- unknown -- rather than an empty
      # list, which would read as "this conversation has no message".
      it 'bounds the fan-out and says what it left unread' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        listed = (1..(described_class::MAX_TIMELINE_READS + 2)).map { |index| conversation(index.to_s) }
        stub_list(*listed)
        stub_request(:get, %r{/conversations/\d+}).to_return(json(conversation_with_parts))

        rows = collection.list(nil, filter, %w[id timeline])

        expect(rows.count { |row| row['timeline'].nil? }).to eq(2)
        expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/left the timeline of 2 row/)
      end
    end
  end
end
