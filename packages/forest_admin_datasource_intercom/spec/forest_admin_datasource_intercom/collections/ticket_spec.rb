module ForestAdminDatasourceIntercom
  RSpec.describe Collections::Ticket do
    subject(:collection) { described_class.new(datasource, attributes: attributes) }

    let(:datasource) { Datasource.new(access_token: 's3cr3t', rate_limiter: nil) }
    # Not read off the datasource: that would build it, and boot the ticket-type
    # introspection before the stub of it exists.
    let(:base) { Configuration::REGION_HOSTS[:us] }
    let(:operators) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators }
    let(:attributes) do
      [Schema::TicketAttributesIntrospector::Attribute.new(name: '_default_title_', column_type: 'String',
                                                           data_type: 'string',
                                                           ids_by_ticket_type: { '1' => '14162161' }),
       Schema::TicketAttributesIntrospector::Attribute.new(name: 'Due', column_type: 'Date', data_type: 'datetime',
                                                           ids_by_ticket_type: { '2' => '9002' })]
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

      # `/tickets/search` filters none of these and ignores a sort without
      # saying so, so nothing but the primary key may advertise anything.
      it 'declares every column unfilterable and unsortable, except the primary key' do
        others = collection.fields.except('id')

        expect(others.values.map(&:filter_operators).flatten.uniq).to be_empty
        expect(others.values.map(&:is_sortable).uniq).to eq([false])
      end

      # An attribute overwriting a native column would show the attribute where
      # the operator expects the ticket field.
      it 'skips an attribute whose name a native column already carries' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        clashing = Schema::TicketAttributesIntrospector::Attribute.new(name: 'category', column_type: 'String',
                                                                       data_type: 'string', ids_by_ticket_type: {})

        collection = described_class.new(datasource, attributes: [clashing])

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

      it 'refuses a condition it cannot honour' do
        expect { rows(%w[id], condition_tree: leaf('state_category', operators::EQUAL, 'resolved')) }
          .to raise_error(UnsupportedOperatorError, /cannot answer a condition/)
      end
    end

    describe '#aggregate' do
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
