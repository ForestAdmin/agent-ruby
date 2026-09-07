module ForestAdminDatasourceIntercom
  RSpec.describe Collections::Contact do
    subject(:collection) { datasource.get_collection('IntercomContact') }

    let(:datasource) { Datasource.new(access_token: 's3cr3t', rate_limiter: nil) }
    let(:base) { datasource.configuration.url }
    let(:operators) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators }

    def json(payload, status = 200)
      { status: status, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end

    def leaf(field, operator, value = nil)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
        .new(field, operator, value)
    end

    def branch(aggregator, *conditions)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch
        .new(aggregator, conditions)
    end

    def filter(condition_tree: nil, page: nil, sort: nil, search: nil)
      ForestAdminDatasourceToolkit::Components::Query::Filter.new(condition_tree: condition_tree, page: page,
                                                                  sort: sort, search: search)
    end

    def page(offset, limit)
      ForestAdminDatasourceToolkit::Components::Query::Page.new(offset: offset, limit: limit)
    end

    def sort(*clauses)
      ForestAdminDatasourceToolkit::Components::Query::Sort.new(clauses)
    end

    def contact(id, overrides = {})
      { 'type' => 'contact', 'id' => id, 'role' => 'user', 'name' => "Contact #{id}",
        'email' => "#{id}@acme.test", 'phone' => nil, 'external_id' => "ext-#{id}", 'owner_id' => 493_881,
        'created_at' => 1_700_000_000, 'updated_at' => 1_700_000_600, 'session_count' => 3,
        'unsubscribed_from_emails' => false, 'has_hard_bounced' => false, 'marked_email_as_spam' => false,
        'browser' => 'chrome', 'browser_language' => 'fr', 'os' => 'OS X', 'language_override' => nil,
        'location' => { 'type' => 'location', 'country' => 'France', 'region' => 'IdF', 'city' => 'Paris' },
        'companies' => { 'type' => 'list', 'data' => [{ 'type' => 'company', 'id' => 'co1' }],
                         'total_count' => 2 },
        'custom_attributes' => {} }.merge(overrides)
    end

    def stub_list(*contacts, cursor: nil)
      pages = cursor ? { 'next' => { 'starting_after' => cursor } } : {}
      stub_request(:get, "#{base}/contacts").with(query: hash_including({}))
                                            .to_return(json('type' => 'list', 'data' => contacts,
                                                            'total_count' => contacts.size, 'pages' => pages))
    end

    def stub_search(*contacts, total: nil)
      stub_request(:post, "#{base}/contacts/search")
        .to_return(json('type' => 'list', 'data' => contacts, 'total_count' => total || contacts.size,
                        'pages' => {}))
    end

    def rows(projection = %w[id], **options)
      collection.list(nil, filter(**options), projection)
    end

    describe 'schema' do
      it 'is named IntercomContact' do
        expect(collection.name).to eq('IntercomContact')
      end

      it 'publishes the columns of a contact, the account it belongs to included' do
        expect(collection.fields.keys)
          .to include('id', 'role', 'name', 'email', 'email_domain', 'phone', 'external_id', 'avatar',
                      'owner_id', 'company_id', 'company_count', 'session_count', 'created_at',
                      'last_seen_at', 'unsubscribed_from_emails', 'location_country')
      end

      it 'publishes every column read-only, this lot writing nothing' do
        columns = collection.fields.values.grep(ForestAdminDatasourceToolkit::Schema::ColumnSchema)

        expect(columns.map(&:is_read_only).uniq).to eq([true])
      end

      # The measured asymmetry: `/contacts/search` refuses `>=`, `<=`, `!=` and
      # `IN` on a date where the other two endpoints take them. A Date column
      # publishes the two bounds alone anyway -- declaring `equal` would make
      # the toolkit republish `in`, which its own validator then refuses
      # (PRD-989) -- so what the restriction really has to guarantee is that
      # nothing wider reaches the wire.
      it 'offers the two bounds on a date, and nothing the endpoint refuses' do
        expect(collection.fields['created_at'].filter_operators).to eq(%w[greater_than less_than])
        expect(collection.fields['last_seen_at'].filter_operators).to eq(%w[greater_than less_than])
      end

      it 'offers on a text column exactly what the table measured' do
        expect(collection.fields['email'].filter_operators)
          .to eq(%w[equal not_equal contains i_contains not_contains starts_with ends_with])
        expect(collection.fields['role'].filter_operators).to eq(%w[equal not_equal])
      end

      # A column the table does not carry advertises nothing, which is how a
      # refusal is spelled in a schema.
      it 'advertises no filter on a column the endpoint does not filter' do
        %w[avatar company_id company_count session_count].each do |column|
          expect(collection.fields[column].filter_operators).to be_empty, "#{column} advertises a filter"
        end
      end

      # The one collection of the whole API Intercom sorts, and the reason this
      # tier reads a `sortable` flag off the measured table at all.
      it 'is sortable on the columns the table measured, and on no others' do
        sortable = collection.fields.select { |_, f| f.respond_to?(:is_sortable) && f.is_sortable }.keys

        expect(sortable).to contain_exactly('name', 'email', 'created_at', 'updated_at', 'signed_up_at',
                                            'last_seen_at', 'last_contacted_at', 'last_replied_at')
      end

      it 'declares the relations the 360 degrees is walked through' do
        expect(collection.fields['owner']).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
        expect(collection.fields['company']).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
        expect(collection.fields['conversations'])
          .to be_a(ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema)
        expect(collection.fields['tickets'].origin_key).to eq('contact_id')
      end

      it 'is countable, total_count being exact on every answer' do
        expect(collection.is_countable?).to be(true)
      end

      it 'is searchable on the address an ops team types' do
        expect(collection.is_searchable?).to be(true)
      end
    end

    describe 'the custom attributes' do
      subject(:collection) { datasource.get_collection('IntercomContact') }

      before do
        stub_data_attributes('contact',
                             { 'name' => 'paid_subscriber', 'data_type' => 'boolean', 'custom' => true,
                               'api_writable' => true, 'archived' => false },
                             { 'name' => 'email', 'data_type' => 'string', 'custom' => false,
                               'api_writable' => false, 'archived' => false })
      end

      it 'publishes one column per custom attribute, typed from the introspection' do
        expect(collection.fields['paid_subscriber'].column_type).to eq('Boolean')
      end

      # Display-only: which operators Intercom answers on
      # `custom_attributes.{name}` has not been measured, and this package
      # publishes no filter it has not seen work.
      it 'publishes it unfilterable and unsortable' do
        expect(collection.fields['paid_subscriber'].filter_operators).to be_empty
        expect(collection.fields['paid_subscriber'].is_sortable).to be(false)
      end

      it 'reads its value off the payload, nil where the contact carries none' do
        stub_list(contact('1', 'custom_attributes' => { 'paid_subscriber' => true }), contact('2'))

        expect(rows(%w[id paid_subscriber]))
          .to eq([{ 'id' => '1', 'paid_subscriber' => true }, { 'id' => '2', 'paid_subscriber' => nil }])
      end
    end

    describe '#list' do
      it 'walks the listing endpoint when nothing is filtered, sorted or searched' do
        stub_list(contact('1'), contact('2'))

        expect(rows).to eq([{ 'id' => '1' }, { 'id' => '2' }])
        expect(WebMock).not_to have_requested(:post, "#{base}/contacts/search")
      end

      it 'flattens the payload onto the row' do
        stub_list(contact('1'))

        expect(rows(nil).first)
          .to include('id' => '1', 'role' => 'user', 'email' => '1@acme.test', 'email_domain' => 'acme.test',
                      'owner_id' => '493881', 'session_count' => 3, 'created_at' => '2023-11-14T22:13:20Z',
                      'location_country' => 'France', 'location_city' => 'Paris')
      end

      # A contact belongs to several accounts: the row names the first and says
      # how many there are, which Intercom counts itself -- the nested list is
      # capped and a contact of twelve accounts must not read as one of ten.
      it 'names the first account and takes the count from Intercom' do
        stub_list(contact('1'))

        expect(rows(nil).first).to include('company_id' => 'co1', 'company_count' => 2)
      end

      it 'counts the accounts it can see when Intercom sends no count' do
        stub_list(contact('1', 'companies' => { 'type' => 'list', 'data' => [{ 'id' => 'co1' }] }))

        expect(rows(nil).first).to include('company_count' => 1)
      end

      it 'leaves the account columns empty on a contact belonging to none' do
        stub_list(contact('1', 'companies' => nil))

        expect(rows(nil).first).to include('company_id' => nil, 'company_count' => 0)
      end

      it 'reads no domain out of an address that has none' do
        stub_list(contact('1', 'email' => nil))

        expect(rows(nil).first).to include('email_domain' => nil)
      end

      it 'translates a filter into the search DSL' do
        stub_search(contact('1'))

        expect(rows(%w[id], condition_tree: leaf('role', operators::EQUAL, 'lead'))).to eq([{ 'id' => '1' }])
        expect(WebMock).to have_requested(:post, "#{base}/contacts/search")
          .with(body: hash_including('query' => { 'field' => 'role', 'operator' => '=', 'value' => 'lead' }))
      end

      it 'answers a free-text search on the address, per word' do
        stub_search(contact('1'))

        rows(%w[id], search: 'acme.test')

        expect(WebMock).to have_requested(:post, "#{base}/contacts/search")
          .with(body: hash_including('query' => { 'field' => 'email', 'operator' => '~', 'value' => 'acme.test' }))
      end
    end

    describe 'the one collection Intercom sorts' do
      # A list view asking for an order has no condition to send, and the
      # listing endpoint does not sort: the order is what routes the read
      # through the search, with the predicate that matches everything.
      it 'sends the order to the search endpoint, with the match-all predicate' do
        stub_search(contact('1'))

        rows(%w[id], sort: sort({ field: 'last_seen_at', ascending: false }))

        expect(WebMock).to have_requested(:post, "#{base}/contacts/search")
          .with(body: hash_including('query' => described_class::MATCH_EVERY_CONTACT,
                                     'sort' => { 'field' => 'last_seen_at', 'order' => 'descending' }))
      end

      it 'sends it alongside the filter when there is one' do
        stub_search(contact('1'))

        rows(%w[id], condition_tree: leaf('role', operators::EQUAL, 'user'),
                     sort: sort({ field: 'name', ascending: true }))

        expect(WebMock).to have_requested(:post, "#{base}/contacts/search")
          .with(body: hash_including('query' => { 'field' => 'role', 'operator' => '=', 'value' => 'user' },
                                     'sort' => { 'field' => 'name', 'order' => 'ascending' }))
      end

      # The ascending primary-key sort the agent injects when a request names
      # none is not an order anybody asked for, and this endpoint does not sort
      # on an id anyway.
      it 'keeps the listing route for the default primary-key order, and says nothing' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_list(contact('1'))

        rows(%w[id], sort: sort({ field: 'id', ascending: true }))

        expect(WebMock).to have_requested(:get, "#{base}/contacts").with(query: hash_including({}))
        expect(ForestAdminDatasourceIntercom.logger).not_to have_received(:warn)
      end

      it 'reports an order on a column Intercom does not sort, rather than dropping it' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_list(contact('1'))

        rows(%w[id], sort: sort({ field: 'browser', ascending: true }))

        expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/sort on browser/)
        expect(WebMock).not_to have_requested(:post, "#{base}/contacts/search")
      end

      # Intercom takes a single `{ field, order }`: honouring the first clause
      # alone would order the page by something the operator did not ask for.
      it 'reports a composite order rather than honouring half of it' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_list(contact('1'))

        rows(%w[id], sort: sort({ field: 'name', ascending: true }, { field: 'email', ascending: false }))

        expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/sort on name, email/)
      end
    end

    describe 'reading records by id' do
      # One request per hundred ids rather than one per id: this endpoint
      # answers `id IN [...]`, which is what makes a related list of contacts
      # affordable at all.
      it 'reads a set of ids in one request through the search' do
        stub_search(contact('1'), contact('2'))

        expect(rows(%w[id], condition_tree: leaf('id', operators::IN, %w[1 2])))
          .to eq([{ 'id' => '1' }, { 'id' => '2' }])
        expect(WebMock).to have_requested(:post, "#{base}/contacts/search")
          .with(body: hash_including('query' => { 'field' => 'id', 'operator' => 'IN', 'value' => %w[1 2] })).once
      end

      it 'reads a record detail the same way' do
        stub_search(contact('1'))

        expect(rows(%w[id], condition_tree: leaf('id', operators::EQUAL, '1'))).to eq([{ 'id' => '1' }])
      end

      # A contact merged into another disappears from the search: the row reads
      # as gone rather than as an error, which is what a merge means.
      it 'answers no row for a contact that was merged away' do
        stub_search

        expect(rows(%w[id], condition_tree: leaf('id', operators::EQUAL, 'merged'))).to be_empty
      end

      it 'counts what the ids named' do
        stub_search(contact('1'))

        expect(collection.aggregate(nil, filter(condition_tree: leaf('id', operators::EQUAL, '1')),
                                    ForestAdminDatasourceToolkit::Components::Query::Aggregation
                                      .new(operation: 'Count')))
          .to eq([{ 'group' => {}, 'value' => 1 }])
      end

      it 'truncates a set larger than it will read, and says so' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_search(contact('1'))

        rows(%w[id], condition_tree: leaf('id', operators::IN, (1..400).map(&:to_s)))

        expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/asked for 400 records by id/)
        expect(WebMock).to have_requested(:post, "#{base}/contacts/search").times(3)
      end
    end

    describe 'the contacts of an account' do
      # `/contacts/search` filters no company field, and `GET
      # /companies/{id}/contacts` is what answers the one relation an ops team
      # walks the most. Without this route it would be a refusal.
      it 'reads them from the company endpoint rather than from the search' do
        stub_request(:get, "#{base}/companies/co1/contacts").with(query: hash_including({}))
                                                            .to_return(json('type' => 'list', 'data' => [contact('1')],
                                                                            'total_count' => 1, 'pages' => {}))

        expect(rows(%w[id], condition_tree: leaf('company_id', operators::EQUAL, 'co1')))
          .to eq([{ 'id' => '1' }])
        expect(WebMock).not_to have_requested(:post, "#{base}/contacts/search")
      end

      it 'counts them from the same endpoint' do
        stub_request(:get, "#{base}/companies/co1/contacts").with(query: hash_including({}))
                                                            .to_return(json('type' => 'list', 'data' => [contact('1')],
                                                                            'total_count' => 42, 'pages' => {}))

        expect(collection.aggregate(nil, filter(condition_tree: leaf('company_id', operators::EQUAL, 'co1')),
                                    ForestAdminDatasourceToolkit::Components::Query::Aggregation
                                      .new(operation: 'Count')))
          .to eq([{ 'group' => {}, 'value' => 42 }])
      end

      it 'reports an order this route cannot apply' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_request(:get, "#{base}/companies/co1/contacts").with(query: hash_including({}))
                                                            .to_return(json('type' => 'list', 'data' => [contact('1')],
                                                                            'total_count' => 1, 'pages' => {}))

        rows(%w[id], condition_tree: leaf('company_id', operators::EQUAL, 'co1'),
                     sort: sort({ field: 'name', ascending: true }))

        expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/sort on name/)
      end

      # An `and` also carrying a scope names a narrower set than the account
      # does, and answering it with the account alone would serve contacts the
      # scope excludes.
      it 'refuses to take the route for anything but a bare equality' do
        expect do
          rows(%w[id], condition_tree: branch('And', leaf('company_id', operators::EQUAL, 'co1'),
                                              leaf('role', operators::EQUAL, 'user')))
        end.to raise_error(UnsupportedOperatorError, /cannot filter "company_id"/)
      end
    end

    describe 'a condition through a relation' do
      def stub_admins(*admins)
        stub_request(:get, "#{base}/admins").to_return(json('type' => 'admin.list', 'admins' => admins))
      end

      # The owner is a teammate, read whole in one request, and
      # `/contacts/search` filters on the key: readable, navigable and
      # filterable alike.
      it 'resolves the owner against the teammates and filters on the key' do
        stub_admins({ 'id' => '493881', 'name' => 'Marie' })
        stub_search(contact('1'))

        rows(%w[id], condition_tree: leaf('owner:name', operators::EQUAL, 'Marie'))

        expect(WebMock).to have_requested(:post, "#{base}/contacts/search")
          .with(body: hash_including('query' => { 'field' => 'owner_id', 'operator' => '=', 'value' => '493881' }))
      end

      it 'nests the owner under the relation when the projection names it' do
        stub_admins({ 'id' => '493881', 'name' => 'Marie' })
        stub_list(contact('1'))

        expect(rows(%w[id owner:name]).first).to eq('id' => '1',
                                                    'owner' => { 'id' => '493881', 'name' => 'Marie' })
      end

      # The endpoint filters no company field, so the relation is there to be
      # read and navigated. Refused by name, before the target is read: a
      # refusal that spends a request costs exactly what it refuses to do.
      it 'refuses a condition through the company, and says what to filter instead' do
        expect { rows(%w[id], condition_tree: leaf('company:name', operators::EQUAL, 'Acme')) }
          .to raise_error(UnsupportedOperatorError,
                          %r{resolves to "company_id", on which contacts/search takes no filter})
        expect(WebMock).not_to have_requested(:post, /companies/)
      end
    end

    describe 'what it will not do' do
      it 'refuses to group, Intercom exposing no aggregate endpoint' do
        expect do
          collection.aggregate(nil, filter, ForestAdminDatasourceToolkit::Components::Query::Aggregation
            .new(operation: 'Count', groups: [{ field: 'role' }]))
        end.to raise_error(UnsupportedOperatorError, /can only be counted/)
      end

      it 'counts what the filter names in one request' do
        stub_search(contact('1'), total: 812)

        expect(collection.aggregate(nil, filter(condition_tree: leaf('role', operators::EQUAL, 'user')),
                                    ForestAdminDatasourceToolkit::Components::Query::Aggregation
                                      .new(operation: 'Count')))
          .to eq([{ 'group' => {}, 'value' => 812 }])
      end
    end

    describe 'paging' do
      it 'asks Intercom for the window the list view named' do
        stub_list(contact('1'), contact('2'), contact('3'))

        expect(rows(%w[id], page: page(1, 2)).map { |row| row['id'] }).to eq(%w[2 3])
      end
    end
  end
end
