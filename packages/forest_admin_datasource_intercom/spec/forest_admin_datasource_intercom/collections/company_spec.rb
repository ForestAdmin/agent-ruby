module ForestAdminDatasourceIntercom
  # The offset tier is exercised through Companies, the one collection Intercom
  # paginates that way -- and the only one it does not search at all.
  RSpec.describe Collections::Company do
    subject(:collection) { datasource.get_collection('IntercomCompany') }

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

    def count(condition_tree: nil)
      collection.aggregate(nil, filter(condition_tree: condition_tree),
                           ForestAdminDatasourceToolkit::Components::Query::Aggregation.new(operation: 'Count'))
    end

    def company(id, overrides = {})
      { 'type' => 'company', 'id' => id, 'company_id' => "erp-#{id}", 'name' => "Company #{id}",
        'plan' => { 'type' => 'plan', 'id' => '9', 'name' => 'Paid' }, 'size' => 85,
        'industry' => 'Manufacturing', 'website' => 'https://acme.test', 'monthly_spend' => 49,
        'session_count' => 26, 'user_count' => 10, 'created_at' => 1_700_000_000,
        'updated_at' => 1_700_000_600, 'last_request_at' => 1_700_000_900,
        'remote_created_at' => 1_394_531_169, 'custom_attributes' => {} }.merge(overrides)
    end

    def stub_page(*companies, page: 1, per_page: 15, total_pages: 1, total: nil)
      stub_request(:post, "#{base}/companies/list")
        .with(query: { 'page' => page.to_s, 'per_page' => per_page.to_s })
        .to_return(json('type' => 'list', 'data' => companies, 'total_count' => total || companies.size,
                        'pages' => { 'type' => 'pages', 'page' => page, 'per_page' => per_page,
                                     'total_pages' => total_pages }))
    end

    def rows(projection = %w[id], **options)
      collection.list(nil, filter(**options), projection)
    end

    describe 'schema' do
      it 'is named IntercomCompany' do
        expect(collection.name).to eq('IntercomCompany')
      end

      it 'publishes the columns of an account' do
        expect(collection.fields.keys)
          .to include('id', 'company_id', 'name', 'plan_name', 'size', 'industry', 'website',
                      'monthly_spend', 'user_count', 'session_count', 'created_at', 'remote_created_at')
      end

      it 'publishes every column read-only and unsortable' do
        columns = collection.fields.values.grep(ForestAdminDatasourceToolkit::Schema::ColumnSchema)

        expect(columns.map(&:is_read_only).uniq).to eq([true])
        expect(columns.map(&:is_sortable).uniq).to eq([false])
      end

      # Four lookups is what `GET /companies` answers, and two of them name a
      # column of this collection. A tag and a segment are collections of their
      # own, and filtering by them belongs with the lot that adds them.
      it 'offers a filter on the two keys Intercom looks a company up by' do
        expect(collection.fields['name'].filter_operators).to eq(%w[equal])
        expect(collection.fields['company_id'].filter_operators).to eq(%w[equal])
        expect(collection.fields['id'].filter_operators).to eq(%w[equal in])
      end

      it 'offers no filter on anything else' do
        %w[plan_name size industry website monthly_spend user_count created_at].each do |column|
          expect(collection.fields[column].filter_operators).to be_empty, "#{column} advertises a filter"
        end
      end

      it 'declares the contacts of the account' do
        expect(collection.fields['contacts'].origin_key).to eq('company_id')
      end

      it 'is countable, total_count being exact on every answer' do
        expect(collection.is_countable?).to be(true)
      end
    end

    describe 'the custom attributes' do
      before do
        stub_data_attributes('company',
                             { 'name' => 'arr', 'data_type' => 'float', 'custom' => true,
                               'api_writable' => true, 'archived' => false })
      end

      it 'publishes one column per attribute, typed and display-only' do
        expect(collection.fields['arr'].column_type).to eq('Number')
        expect(collection.fields['arr'].filter_operators).to be_empty
      end

      it 'skips an attribute whose name a native column already carries, and says which' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_data_attributes('company', { 'name' => 'name', 'data_type' => 'string', 'custom' => true,
                                          'api_writable' => true, 'archived' => false })
        stub_page(company('co1', 'custom_attributes' => { 'name' => 'Not the account name' }),
                  page: 1, per_page: 15)

        expect(rows(nil, page: page(0, 15)).first['name']).to eq('Company co1')
        expect(ForestAdminDatasourceIntercom.logger)
          .to have_received(:warn).with(/skips the company attribute "name"/)
      end

      it 'reads a date attribute as a date' do
        stub_data_attributes('company', { 'name' => 'renewal', 'data_type' => 'date', 'custom' => true,
                                          'api_writable' => true, 'archived' => false })
        stub_page(company('co1', 'custom_attributes' => { 'renewal' => 1_700_000_000 }), page: 1, per_page: 15)

        expect(rows(%w[id renewal], page: page(0, 15)).first['renewal']).to eq('2023-11-14T22:13:20Z')
      end

      it 'reads its value off the payload' do
        stub_page(company('co1', 'custom_attributes' => { 'arr' => 12_000 }))

        expect(rows(%w[id arr], page: page(0, 15))).to eq([{ 'id' => 'co1', 'arr' => 12_000 }])
      end
    end

    describe 'pagination by offset' do
      # The one place R1 does not apply: Intercom counts pages, which is what a
      # list view asks for. No cursor walked, no page read to be thrown away.
      it 'asks for the page the window names, in one request' do
        stub_page(company('co1'), page: 3, per_page: 15, total_pages: 3)

        expect(rows(%w[id], page: page(30, 15))).to eq([{ 'id' => 'co1' }])
        expect(WebMock).to have_requested(:post, "#{base}/companies/list")
          .with(query: { 'page' => '3', 'per_page' => '15' }).once
      end

      # An offset that does not fall on a page boundary is served exactly, by
      # reading the page it lands in and the next -- never by rounding the
      # window to something the API likes better.
      it 'reads across two pages when the window straddles them' do
        stub_page(company('a'), company('b'), page: 1, per_page: 2, total_pages: 3)
        stub_page(company('c'), company('d'), page: 2, per_page: 2, total_pages: 3)

        expect(rows(%w[id], page: page(1, 2)).map { |row| row['id'] }).to eq(%w[b c])
      end

      it 'stops at the last page rather than asking for one past it' do
        stub_page(company('a'), page: 1, per_page: 15, total_pages: 1)

        expect(rows(%w[id], page: page(0, 15)).size).to eq(1)
        expect(WebMock).not_to have_requested(:post, "#{base}/companies/list")
          .with(query: { 'page' => '2', 'per_page' => '15' })
      end

      it 'stops on a page Intercom answers empty' do
        stub_page(page: 1, per_page: 2, total_pages: 9)

        expect(rows(%w[id], page: page(0, 2))).to be_empty
      end

      # A read naming no window -- a segment, a customizer -- is the only one
      # that can run long, and it is the only one this bounds.
      it 'reads full pages when the read names no window' do
        stub_page(company('a'), page: 1, per_page: 150, total_pages: 1)

        expect(rows(%w[id]).map { |row| row['id'] }).to eq(%w[a])
      end

      it 'stops such a read after the pages it allows, and says so' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        (1..10).each { |number| stub_page(company("c#{number}"), page: number, per_page: 150, total_pages: 99) }

        expect(rows(%w[id]).size).to eq(10)
        expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/Stopped reading IntercomCompany/)
      end

      it 'counts what Intercom counted, in one request' do
        stub_page(company('a'), page: 1, per_page: 1, total_pages: 40, total: 597)

        expect(count).to eq([{ 'group' => {}, 'value' => 597 }])
      end

      # Counting the pages read would answer a fraction of the collection as if
      # it were the whole of it.
      it 'refuses to count a listing Intercom answered without a total' do
        stub_request(:post, "#{base}/companies/list").with(query: hash_including({}))
                                                     .to_return(json('type' => 'list', 'data' => [company('a')],
                                                                     'pages' => {}))

        expect { count }.to raise_error(UnsupportedOperatorError, /cannot be counted/)
      end
    end

    describe 'the four lookups, and everything past them' do
      it 'reads a record detail through its own endpoint' do
        stub_request(:get, "#{base}/companies/co1").to_return(json(company('co1')))

        expect(rows(%w[id], condition_tree: leaf('id', operators::EQUAL, 'co1'))).to eq([{ 'id' => 'co1' }])
      end

      it 'reads a set of ids one request each' do
        stub_request(:get, "#{base}/companies/co1").to_return(json(company('co1')))
        stub_request(:get, "#{base}/companies/co2").to_return(json(company('co2')))

        expect(rows(%w[id], condition_tree: leaf('id', operators::IN, %w[co1 co2])).map { |row| row['id'] })
          .to eq(%w[co1 co2])
      end

      it 'reads a company the token can no longer reach as no record' do
        stub_request(:get, "#{base}/companies/co1").to_return(json({ 'type' => 'error.list' }, 404))

        expect(rows(%w[id], condition_tree: leaf('id', operators::EQUAL, 'co1'))).to be_empty
      end

      it 'raises on a failure that is not a missing record' do
        stub_request(:get, "#{base}/companies/co1").to_return(json({ 'type' => 'error.list' }, 500))

        expect { rows(%w[id], condition_tree: leaf('id', operators::EQUAL, 'co1')) }.to raise_error(APIError)
      end

      it 'truncates a set of ids larger than it will read, and says so' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_request(:get, %r{#{base}/companies/co\d+}).to_return(json(company('co1')))

        rows(%w[id], condition_tree: leaf('id', operators::IN, (1..30).map { |n| "co#{n}" }))

        expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/asked for 30 records by id/)
      end

      it 'counts the records the ids named' do
        stub_request(:get, "#{base}/companies/co1").to_return(json(company('co1')))

        expect(count(condition_tree: leaf('id', operators::EQUAL, 'co1'))).to eq([{ 'group' => {}, 'value' => 1 }])
      end

      # `GET /companies?name=` answers the company itself where a listing would
      # answer an envelope: a record is read as a page of one rather than as a
      # shape every caller has to test for.
      it 'looks a company up by name, and reads the record Intercom answers' do
        stub_request(:get, "#{base}/companies").with(query: { 'name' => 'Acme' })
                                               .to_return(json(company('co1')))

        expect(rows(%w[id], condition_tree: leaf('name', operators::EQUAL, 'Acme'))).to eq([{ 'id' => 'co1' }])
      end

      it 'looks one up by the identifier the workspace gave it' do
        stub_request(:get, "#{base}/companies").with(query: { 'company_id' => 'erp-co1' })
                                               .to_return(json('type' => 'list', 'data' => [company('co1')],
                                                               'total_count' => 1, 'pages' => {}))

        expect(rows(%w[id], condition_tree: leaf('company_id', operators::EQUAL, 'erp-co1')))
          .to eq([{ 'id' => 'co1' }])
      end

      it 'counts what a lookup found' do
        stub_request(:get, "#{base}/companies").with(query: { 'name' => 'Acme' })
                                               .to_return(json(company('co1')))

        expect(count(condition_tree: leaf('name', operators::EQUAL, 'Acme')))
          .to eq([{ 'group' => {}, 'value' => 1 }])
      end

      it 'reports a lookup Intercom answered with more than one page' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_request(:get, "#{base}/companies").with(query: { 'name' => 'Acme' })
                                               .to_return(json('type' => 'list', 'data' => [company('co1')],
                                                               'pages' => { 'next' => { 'starting_after' => 'zzz' } }))

        rows(%w[id], condition_tree: leaf('name', operators::EQUAL, 'Acme'))

        expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/advertised more records/)
      end

      # A filter this collection cannot look up is refused by name. A page
      # served in answer to a filter it ignored is the one failure this
      # datasource is built to avoid.
      it 'refuses a filter on a column Intercom does not look up' do
        expect { rows(%w[id], condition_tree: leaf('industry', operators::EQUAL, 'Manufacturing')) }
          .to raise_error(UnsupportedOperatorError, /cannot filter "industry".*name, company_id alone/m)
      end

      it 'refuses an operator the lookup has no equivalent for' do
        expect { rows(%w[id], condition_tree: leaf('name', operators::CONTAINS, 'Acm')) }
          .to raise_error(UnsupportedOperatorError, /cannot filter "name"/)
      end

      it 'refuses a combination, the lookup answering one value at a time' do
        expect do
          rows(%w[id], condition_tree: branch('And', leaf('name', operators::EQUAL, 'Acme'),
                                              leaf('company_id', operators::EQUAL, 'erp-co1')))
        end.to raise_error(UnsupportedOperatorError, /one exact value at a time/)
      end

      it 'refuses to count what it refuses to list' do
        expect { count(condition_tree: leaf('industry', operators::EQUAL, 'Manufacturing')) }
          .to raise_error(UnsupportedOperatorError, /cannot filter "industry"/)
      end
    end

    describe 'what it will not do' do
      it 'refuses to group, Intercom exposing no aggregate endpoint' do
        expect do
          collection.aggregate(nil, filter, ForestAdminDatasourceToolkit::Components::Query::Aggregation
            .new(operation: 'Count', groups: [{ field: 'industry' }]))
        end.to raise_error(UnsupportedOperatorError, /can only be counted/)
      end

      # There is no order parameter on this listing at all, so an order asked
      # for and not applied is reported here or nowhere.
      it 'reports an order it cannot apply' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_page(company('a'), page: 1, per_page: 15)

        rows(%w[id], page: page(0, 15), sort: sort({ field: 'name', ascending: true }))

        expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/takes no order on this listing/)
      end

      it 'says nothing of the ascending primary-key order the agent injects' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_page(company('a'), page: 1, per_page: 15)

        rows(%w[id], page: page(0, 15), sort: sort({ field: 'id', ascending: true }))

        expect(ForestAdminDatasourceIntercom.logger).not_to have_received(:warn)
      end

      it 'reports an explicit descending order on the key, which it cannot apply either' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_page(company('a'), page: 1, per_page: 15)

        rows(%w[id], page: page(0, 15), sort: sort({ field: 'id', ascending: false }))

        expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/sort on id/)
      end
    end

    describe 'the row' do
      it 'flattens the payload, the plan read off the object that carries it' do
        stub_page(company('co1'), page: 1, per_page: 15)

        expect(rows(nil, page: page(0, 15)).first)
          .to include('id' => 'co1', 'company_id' => 'erp-co1', 'name' => 'Company co1', 'plan_name' => 'Paid',
                      'size' => 85, 'monthly_spend' => 49, 'user_count' => 10,
                      'created_at' => '2023-11-14T22:13:20Z', 'remote_created_at' => '2014-03-11T09:46:09Z')
      end

      it 'reads a company carrying no plan without failing' do
        stub_page(company('co1', 'plan' => nil), page: 1, per_page: 15)

        expect(rows(nil, page: page(0, 15)).first).to include('plan_name' => nil)
      end
    end
  end
end
