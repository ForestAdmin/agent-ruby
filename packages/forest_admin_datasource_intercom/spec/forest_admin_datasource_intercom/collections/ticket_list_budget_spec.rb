module ForestAdminDatasourceIntercom
  # What one page of a list view costs in requests, counted end to end.
  #
  # Every other spec of this package asserts what a collection answers; this one
  # asserts what it spends to answer it, because that is what an operator waits
  # through. Intercom joins nothing, so a page projecting five relations used to
  # be seven sequential round trips -- the page itself, the contacts read twice
  # over, and the four workspace lists re-read on every page.
  #
  # The figures below are the budget. A change that raises one of them is a
  # change that makes the list view slower, and it should have to say so here.
  RSpec.describe Collections::Ticket, '#list' do
    let(:base) { Configuration::REGION_HOSTS[:us] }
    let(:datasource) { Datasource.new(access_token: 's3cr3t', rate_limiter: nil) }

    def json(payload)
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end

    def ticket(id)
      { 'type' => 'ticket', 'id' => id, 'ticket_id' => "1#{id}", 'category' => 'request', 'open' => true,
        'created_at' => 1_700_000_000, 'admin_assignee_id' => 493_881, 'team_assignee_id' => 12,
        'ticket_state' => { 'id' => '19', 'internal_label' => 'En cours' },
        'previous_ticket_state_id' => '14',
        'ticket_type' => { 'id' => '1', 'name' => 'Bug' },
        'contacts' => { 'type' => 'contact.list', 'contacts' => [{ 'id' => "c#{id}" }] },
        'ticket_parts' => { 'type' => 'ticket_part.list', 'ticket_parts' => [] } }
    end

    # Columns and relations both, the way Forest projects a list view: a
    # many-to-one is displayed through a column of its target.
    def projection
      ForestAdminDatasourceToolkit::Components::Query::Projection.new(
        %w[id ticket_id category open created_at state_label contact_name
           admin_assignee:id admin_assignee:name team_assignee:id team_assignee:name
           state:id state:internal_label previous_state:id previous_state:internal_label
           ticket_type:id ticket_type:name contact:id contact:name]
      )
    end

    def list_page(collection = 'IntercomTicket')
      filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
        page: ForestAdminDatasourceToolkit::Components::Query::Page.new(offset: 0, limit: 15)
      )

      datasource.get_collection(collection).list(nil, filter, projection)
    end

    def search_answer
      json('type' => 'ticket.list', 'total_count' => 500, 'pages' => { 'page' => 1 },
           'tickets' => (1..15).map { |index| ticket(index.to_s) })
    end

    # Counted at the HTTP layer rather than per stub: what matters is the number
    # of round trips, whichever endpoint they reach.
    #
    # WebMock registers callbacks globally and offers no way to remove one, so
    # the reset takes every callback with it. Nothing else in this suite
    # registers any -- this is the only spec that counts requests rather than
    # asserting them -- and leaving this one in place would have it counting
    # into a dead hash for the rest of the run.
    def requests_of
      calls = Hash.new(0)
      WebMock.after_request { |request, _| calls["#{request.method.to_s.upcase} #{request.uri.path}"] += 1 }
      yield
      calls
    ensure
      WebMock::CallbackRegistry.reset
    end

    before do
      # The suite stubs `/ticket_types` empty for the boot read every datasource
      # issues; this one installs the type its tickets carry, so the relation
      # resolves to a row rather than to nil and the budget below is the budget
      # of a page that answered.
      stub_ticket_types({ 'id' => '1', 'name' => 'Bug' })
      stub_request(:get, "#{base}/admins")
        .to_return(json('type' => 'admin.list',
                        'admins' => [{ 'id' => '493881', 'name' => 'Alice', 'team_ids' => [12] }]))
      stub_request(:get, "#{base}/teams")
        .to_return(json('type' => 'team.list', 'teams' => [{ 'id' => '12', 'name' => 'Support' }]))
      stub_request(:get, "#{base}/ticket_states")
        .to_return(json('type' => 'list',
                        'data' => [{ 'id' => '19', 'internal_label' => 'En cours' },
                                   { 'id' => '14', 'internal_label' => 'Soumis' }]))
      stub_request(:post, "#{base}/tickets/search").with(query: hash_including({})).to_return(search_answer)
      stub_request(:post, "#{base}/contacts/search")
        .to_return(json('type' => 'list',
                        'data' => (1..15).map { |index| { 'id' => "c#{index}", 'name' => "Contact #{index}" } }))
      # The boot reads, so the counts below are the page's own.
      datasource
    end

    # A budget is only a budget if the page it counts is a page. Without this,
    # a change resolving every relation to nil would spend the same requests and
    # read here as an improvement -- the five reads would still be issued, and
    # nothing would be asserting that any of them landed on a row.
    it 'answers a page whose five relations are resolved' do
      row = list_page.first

      expect(row).to include(
        'id' => '1', 'state_label' => 'En cours', 'contact_name' => 'Contact 1',
        'admin_assignee' => { 'id' => '493881', 'name' => 'Alice' },
        'team_assignee' => { 'id' => '12', 'name' => 'Support' },
        'state' => { 'id' => '19', 'internal_label' => 'En cours' },
        'previous_state' => { 'id' => '14', 'internal_label' => 'Soumis' },
        'ticket_type' => { 'id' => '1', 'name' => 'Bug' },
        'contact' => { 'id' => 'c1', 'name' => 'Contact 1' }
      )
    end

    # The first page after a boot pays for the workspace lists it is the first to
    # need -- three of the four, `/ticket_types` being held from the boot read
    # that introspects the ticket attributes. The contacts are read once for the
    # column and the relation both, where that used to be two requests.
    it 'spends five requests on the first page of tickets, five relations projected' do
      calls = requests_of { list_page }

      expect(calls).to eq('POST /tickets/search' => 1, 'POST /contacts/search' => 1,
                          'GET /admins' => 1, 'GET /teams' => 1, 'GET /ticket_states' => 1)
    end

    # And every page after it, for as long as the window holds: the page itself,
    # and the contacts of the page.
    it 'spends two requests on the next page' do
      list_page
      calls = requests_of { list_page }

      expect(calls).to eq('POST /tickets/search' => 1, 'POST /contacts/search' => 1)
    end

    # The one that cost a request per page and answered the same rows every time.
    it 'reads the contacts of a page once for the column and the relation both' do
      list_page

      expect(WebMock).to have_requested(:post, "#{base}/contacts/search").once
    end

    it 'reads each workspace list once across three pages' do
      calls = requests_of { 3.times { list_page } }

      expect(calls).to eq('POST /tickets/search' => 3, 'POST /contacts/search' => 3,
                          'GET /admins' => 1, 'GET /teams' => 1, 'GET /ticket_states' => 1)
    end

    # Without the two stores, the seven round trips the change was made against.
    context 'with the stores off' do
      let(:datasource) do
        Datasource.new(access_token: 's3cr3t', rate_limiter: nil, reference_cache_ttl: 0)
      end

      it 'spends a request per relation target on every page' do
        calls = requests_of { 3.times { list_page } }

        expect(calls).to include('GET /admins' => 3, 'GET /teams' => 3,
                                 'GET /ticket_states' => 3, 'GET /ticket_types' => 3)
      end
    end
  end
end
