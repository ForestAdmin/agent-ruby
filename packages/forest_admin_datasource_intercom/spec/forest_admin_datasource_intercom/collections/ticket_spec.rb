module ForestAdminDatasourceIntercom
  RSpec.describe Collections::Ticket do
    subject(:collection) { described_class.new(datasource, attributes: attributes) }

    let(:datasource) { Datasource.new(access_token: 's3cr3t', rate_limiter: nil) }
    # Not read off the datasource: that would build it, and boot the ticket-type
    # introspection before the stub of it exists.
    let(:base) { Configuration::REGION_HOSTS[:us] }
    let(:operators) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators }
    let(:attributes) { [attribute('_default_title_'), attribute('Due', column_type: 'Date')] }

    # `column_name` is what the schema publishes and `name` the key the payload
    # uses; they differ when the workspace's own name cannot travel through a
    # Forest query string.
    def attribute(name, column_name: nil, column_type: 'String')
      Schema::TicketAttributesIntrospector::Attribute.new(name: name, column_name: column_name || name,
                                                          column_type: column_type, data_type: 'string',
                                                          ids_by_ticket_type: { '1' => '9001' })
    end

    def json(payload, status = 200)
      { status: status, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end

    def filter(condition_tree: nil, page: nil)
      ForestAdminDatasourceToolkit::Components::Query::Filter.new(condition_tree: condition_tree, page: page)
    end

    def leaf(field, operator, value = nil)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
        .new(field, operator, value)
    end

    # Hand-written from the shape measured on a real workspace: the state comes
    # embedded, the company as a bare id, and the parts ride along.
    def ticket(id, overrides = {})
      { 'type' => 'ticket', 'id' => id, 'ticket_id' => "1#{id}", 'category' => 'request',
        'open' => true, 'is_shared' => false, 'created_at' => 1_700_000_000, 'updated_at' => 1_700_003_600,
        'admin_assignee_id' => 493_881, 'team_assignee_id' => 0,
        'company_id' => '696dd52099f73812610d9c7b',
        'ticket_state' => { 'type' => 'ticket_state', 'id' => '19', 'category' => 'in_progress',
                            'internal_label' => 'En cours Tech', 'external_label' => 'Investigation en cours' },
        'previous_ticket_state_id' => '14',
        'ticket_type' => { 'type' => 'ticket_type', 'id' => '1', 'name' => 'Bug' },
        'contacts' => { 'type' => 'contact.list', 'contacts' => [{ 'type' => 'contact', 'id' => 'c1' }] },
        'ticket_attributes' => { '_default_title_' => 'Facture manquante' },
        'ticket_parts' => { 'type' => 'ticket_part.list', 'total_count' => 0, 'ticket_parts' => [] } }
        .merge(overrides)
    end

    def parts(*entries, total: nil)
      { 'ticket_parts' => { 'type' => 'ticket_part.list', 'total_count' => total || entries.size,
                            'ticket_parts' => entries } }
    end

    def state_change(to, from: 'in_progress', at: 1_700_002_000, by: 'Alice', part_type: nil)
      { 'type' => 'ticket_part', 'id' => "s#{at}", 'part_type' => part_type || 'ticket_state_updated_by_admin',
        'ticket_state' => to, 'previous_ticket_state' => from, 'created_at' => at,
        'author' => { 'type' => 'admin', 'id' => '1', 'name' => by, 'email' => 'alice@acme.test' } }
    end

    def comment(at:, by: 'Alice', type: 'admin', part_type: 'comment')
      { 'type' => 'ticket_part', 'id' => "c#{at}", 'part_type' => part_type, 'body' => 'Je regarde.',
        'created_at' => at, 'author' => { 'type' => type, 'id' => '1', 'name' => by } }
    end

    def stub_search(*records, total: nil, body: nil)
      answer = { 'type' => 'ticket.list', 'tickets' => records, 'total_count' => total || records.size,
                 'pages' => { 'type' => 'pages', 'page' => 1 } }

      request = stub_request(:post, "#{base}/tickets/search")
      request = request.with(body: hash_including(body)) if body
      request.to_return(json(answer))
    end

    def rows(projection = nil, **options)
      collection.list(nil, filter(**options), projection)
    end

    describe 'schema' do
      it 'is named IntercomTicket' do
        expect(collection.name).to eq('IntercomTicket')
      end

      # The state travels embedded, so its labels cost nothing and the row does
      # not depend on IntercomTicketState to be readable.
      it 'flattens the embedded state into its labels' do
        expect(collection.fields.keys)
          .to include('state_id', 'state_category', 'state_label', 'state_external_label', 'previous_state_id')
      end

      it 'carries the attributes of every ticket type in union' do
        expect(collection.fields.keys).to include('_default_title_', 'Due')
        expect(collection.fields['Due'].column_type).to eq('Date')
      end

      # `/tickets/search` ignores a sort without saying so, on every column.
      it 'declares every column unsortable' do
        expect(collection.fields.values.map(&:is_sortable).uniq).to eq([false])
      end

      it 'advertises the filters the search endpoint answers, and only those' do
        expect(collection.fields['category'].filter_operators).to eq(%w[equal not_equal])
        expect(collection.fields['created_at'].filter_operators).to eq(%w[greater_than less_than])
      end

      # Measured during lot 1: `/tickets/search` refuses `company_id` with
      # `invalid_field` although a ticket carries one. Filtering tickets by
      # account is not something this endpoint does.
      it 'advertises no filter on the account, which the endpoint refuses' do
        expect(collection.fields['company_id'].filter_operators).to be_empty
      end

      # Derived by the agent from the parts of the ticket. A column advertising a
      # filter the read cannot honour is what this lot exists to prevent.
      it 'advertises no filter on the columns derived from the parts' do
        %w[closed_at closed_by_name last_reply_at last_responder_name last_responder_type].each do |column|
          expect(collection.fields[column].filter_operators).to be_empty, "#{column} advertises a filter"
        end
      end

      # R7: an attribute is filtered through an id that differs from one ticket
      # type to the next, so the union column cannot say which id to use.
      it 'advertises no filter on a ticket attribute while the arbitration stands' do
        expect(collection.fields['Due'].filter_operators).to be_empty
        expect(collection.fields['_default_title_'].filter_operators).to be_empty
      end

      # Intercom matches text field by field, and this endpoint exposes none
      # this collection carries.
      it 'is not searchable' do
        expect(collection).not_to be_is_searchable
      end

      # An attribute overwriting a native column would show the attribute where
      # the operator expects the ticket field.
      it 'skips an attribute whose name a native column already carries' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)

        collection = described_class.new(datasource, attributes: [attribute('category')])

        expect(collection.fields['category'].column_type).to eq('String')
        expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/skips the ticket attribute/)
      end
    end

    describe '#list' do
      # There is no GET /tickets at all: even an unfiltered list view goes
      # through the search endpoint with a predicate that matches everything.
      it 'reads the search endpoint with a predicate matching every ticket' do
        stub_search(ticket('1'))

        rows(%w[id])

        expect(WebMock).to have_requested(:post, "#{base}/tickets/search")
          .with(body: hash_including('query' => { 'field' => 'created_at', 'operator' => '>', 'value' => '0' }))
      end

      # Not the 150 the API accepts: a page carries every ticket's whole
      # timeline, and there is no way to ask Intercom for less.
      it 'asks for far fewer tickets than the API would allow' do
        stub_search(ticket('1'))

        rows(%w[id])

        pagination = hash_including('per_page' => described_class::MAX_TICKETS_PER_PAGE)

        expect(WebMock).to have_requested(:post, "#{base}/tickets/search")
          .with(body: hash_including('pagination' => pagination))
      end

      it 'reads the records under the tickets key' do
        stub_search(ticket('1'), ticket('2'))

        expect(rows(%w[id]).map { |row| row['id'] }).to eq(%w[1 2])
      end

      it 'flattens the ticket into the row the schema declares' do
        stub_search(ticket('1'))

        expect(rows.first)
          .to include('id' => '1', 'ticket_id' => '11', 'category' => 'request', 'open' => true,
                      'state_id' => '19', 'state_category' => 'in_progress', 'state_label' => 'En cours Tech',
                      'previous_state_id' => '14', 'ticket_type_name' => 'Bug',
                      'company_id' => '696dd52099f73812610d9c7b', 'admin_assignee_id' => '493881')
      end

      # Intercom keys the values by attribute name, which is what lets one
      # collection display the union -- and what stops it from filtering on them.
      it 'reads an attribute value by its name' do
        stub_search(ticket('1'))

        expect(rows.first['_default_title_']).to eq('Facture manquante')
      end

      # Forest lists the fields of a request in a comma-separated query
      # parameter, so a column name carrying one splits the projection into
      # fields no collection has -- a 400 before the page is ever read. The
      # introspector renames such an attribute; the value is still read under the
      # name Intercom keys it by.
      it 'reads a renamed attribute under the name the payload uses' do
        renamed = attribute('ID de l\'objet (immo, facture)', column_name: "ID de l'objet (immo facture)")
        collection = described_class.new(datasource, attributes: [renamed])
        stub_search(ticket('1', 'ticket_attributes' => { 'ID de l\'objet (immo, facture)' => 'immo_42' }))

        row = collection.list(nil, filter, nil).first

        expect(row["ID de l'objet (immo facture)"]).to eq('immo_42')
      end

      # The invariant behind the rename, asserted on the whole schema rather than
      # on one column.
      it 'publishes no column name a Forest query string could not carry' do
        collection = described_class.new(datasource, attributes: [attribute('Scope', column_name: 'Scope')])

        expect(collection.fields.keys.grep(/[,:]/)).to be_empty
      end

      it 'leaves an attribute of another ticket type absent rather than empty' do
        stub_search(ticket('1'))

        expect(rows.first['Due']).to be_nil
      end

      it 'reads a date attribute as ISO8601 like every other Intercom date' do
        stub_search(ticket('1', 'ticket_attributes' => { 'Due' => 1_700_000_000 }))

        expect(rows.first['Due']).to eq('2023-11-14T22:13:20Z')
      end

      # A record detail goes to its own endpoint, which is not the search one.
      it 'reads one ticket through the record endpoint' do
        stub_request(:get, "#{base}/tickets/1").to_return(json(ticket('1')))

        expect(rows(%w[id], condition_tree: leaf('id', operators::EQUAL, '1')).map { |row| row['id'] }).to eq(%w[1])
      end

      # The search carries the filter it was given, in place of the predicate
      # that matches everything.
      it 'searches with the query the translator wrote' do
        search = stub_search(ticket('1'), body: { 'query' => { 'field' => 'category', 'operator' => '=',
                                                               'value' => 'request' } })

        rows(%w[id], condition_tree: leaf('category', operators::EQUAL, 'request'))

        expect(search).to have_been_made
      end

      it 'refuses a condition on a column the endpoint does not filter, by name' do
        expect { rows(%w[id], condition_tree: leaf('state_category', operators::EQUAL, 'resolved')) }
          .to raise_error(UnsupportedOperatorError, /cannot filter "state_category"/)
      end

      # The account, measured as refused by the endpoint itself.
      it 'refuses a condition on the account with the measurement as its reason' do
        expect { rows(%w[id], condition_tree: leaf('company_id', operators::EQUAL, '696dd')) }
          .to raise_error(UnsupportedOperatorError, /invalid_field/)
      end

      it 'refuses a free-text search, having no text column the endpoint matches' do
        searched = ForestAdminDatasourceToolkit::Components::Query::Filter.new(search: 'facture')

        expect { collection.list(nil, searched, %w[id]) }
          .to raise_error(UnsupportedOperatorError, /cannot answer a free-text search/)
      end
    end

    describe '#aggregate' do
      it 'counts a filtered collection through the total_count of its search' do
        stub_search(total: 12, body: { 'query' => { 'field' => 'open', 'operator' => '=', 'value' => true } })
        aggregation = ForestAdminDatasourceToolkit::Components::Query::Aggregation.new(operation: 'Count')

        expect(collection.aggregate(nil, filter(condition_tree: leaf('open', operators::EQUAL, true)),
                                    aggregation).first['value']).to eq(12)
      end

      it 'counts through the total_count of the search, exactly' do
        stub_search(ticket('1'), total: 81_142)
        aggregation = ForestAdminDatasourceToolkit::Components::Query::Aggregation.new(operation: 'Count')

        expect(collection.aggregate(nil, filter, aggregation)).to eq([{ 'group' => {}, 'value' => 81_142 }])
      end
    end

    describe 'the derived columns' do
      # A ticket has no statistics block -- measured on 81 142 tickets -- so the
      # closure date exists nowhere but in the parts, which ride along anyway.
      it 'reads the closure from the last transition into a resolved state' do
        stub_search(ticket('1', **parts(state_change('in_progress', from: 'submitted', at: 1_700_001_000),
                                        state_change('resolved', at: 1_700_002_000, by: 'Alice'))))

        expect(rows.first).to include('closed_at' => '2023-11-14T22:46:40Z', 'closed_by_name' => 'Alice')
      end

      # This workspace runs workflows: a closure done by automation carries
      # another variant of the same event, and matching the admin one in full
      # would make it invisible.
      it 'reads a closure whatever the variant of the state-change event' do
        stub_search(ticket('1', **parts(state_change('resolved', at: 1_700_002_000,
                                                                 part_type: 'ticket_state_updated_by_workflow'))))

        expect(rows.first['closed_at']).to eq('2023-11-14T22:46:40Z')
      end

      # Measured: a part can record a transition to the state the ticket was
      # already in, and that is not an event.
      it 'ignores a transition that changed nothing' do
        stub_search(ticket('1', **parts(state_change('resolved', from: 'resolved', at: 1_700_002_000))))

        expect(rows.first['closed_at']).to be_nil
      end

      it 'keeps the last closure of a ticket that was reopened' do
        stub_search(ticket('1', **parts(state_change('resolved', at: 1_700_001_000),
                                        state_change('in_progress', from: 'resolved', at: 1_700_001_500),
                                        state_change('resolved', at: 1_700_002_000))))

        expect(rows.first['closed_at']).to eq('2023-11-14T22:46:40Z')
      end

      it 'names the last responder and which side they are on' do
        stub_search(ticket('1', **parts(comment(at: 1_700_001_000, by: 'Alice'),
                                        comment(at: 1_700_002_000, by: 'Camille', type: 'contact'))))

        expect(rows.first)
          .to include('last_reply_at' => '2023-11-14T22:46:40Z', 'last_responder_name' => 'Camille',
                      'last_responder_type' => 'contact')
      end

      # An internal note is a touch, not an answer: it would name as last
      # responder someone who never wrote to the person waiting.
      it 'ignores an internal note' do
        stub_search(ticket('1', **parts(comment(at: 1_700_001_000, by: 'Alice'),
                                        comment(at: 1_700_002_000, by: 'Bob', part_type: 'note'))))

        expect(rows.first['last_responder_name']).to eq('Alice')
      end

      it 'leaves both columns empty on a ticket nothing happened to' do
        stub_search(ticket('1'))

        expect(rows.first).to include('closed_at' => nil, 'last_responder_name' => nil)
      end

      # Intercom keeps the 500 most recent parts. A resolved ticket whose
      # transition fell out of that window has an *unknown* closure date, not an
      # absent one -- a Date column cannot say it, so the log does.
      it 'reports a resolved ticket whose timeline was truncated' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        resolved = { 'ticket_state' => { 'id' => '20', 'category' => 'resolved', 'internal_label' => 'Resolu' } }
        stub_search(ticket('1', **resolved, **parts(comment(at: 1_700_001_000), total: 500)))

        rows(%w[id closed_at])

        expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/truncated their timeline/)
      end

      it 'stays quiet when the closure is simply absent from a complete timeline' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_search(ticket('1', **parts(comment(at: 1_700_001_000))))

        rows(%w[id closed_at])

        expect(ForestAdminDatasourceIntercom.logger).not_to have_received(:warn)
      end
    end
  end
end
