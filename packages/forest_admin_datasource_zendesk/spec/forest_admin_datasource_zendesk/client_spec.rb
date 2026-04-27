RSpec.describe ForestAdminDatasourceZendesk::Client do
  let(:configuration) do
    ForestAdminDatasourceZendesk::Configuration.new(
      subdomain: 'acme', username: 'agent@acme.com/token', token: 'secret'
    )
  end
  let(:client) { described_class.new(configuration) }
  let(:base) { 'https://acme.zendesk.com/api/v2' }

  def empty_search_response
    { status: 200, body: { 'results' => [] }.to_json,
      headers: { 'Content-Type' => 'application/json' } }
  end

  describe '#search' do
    it 'prefixes the query with type:<resource> when caller passes nothing' do
      stub = stub_request(:get, "#{base}/search")
             .with(query: hash_including('query' => 'type:ticket'))
             .to_return(empty_search_response)

      client.search('ticket', query: '')
      expect(stub).to have_been_requested
    end

    it 'composes type:<resource> with the caller-supplied query' do
      stub = stub_request(:get, "#{base}/search")
             .with(query: hash_including('query' => 'type:user role:end-user'))
             .to_return(empty_search_response)

      client.search('user', query: 'role:end-user')
      expect(stub).to have_been_requested
    end

    it 'caps per_page at MAX_PER_PAGE' do
      stub = stub_request(:get, "#{base}/search")
             .with(query: hash_including('per_page' => '100'))
             .to_return(empty_search_response)

      client.search('ticket', query: '', per_page: 999)
      expect(stub).to have_been_requested
    end

    it 'forwards sort_by and sort_order' do
      stub = stub_request(:get, "#{base}/search")
             .with(query: hash_including('sort_by' => 'updated_at', 'sort_order' => 'desc'))
             .to_return(empty_search_response)

      client.search('ticket', query: '', sort_by: 'updated_at', sort_order: 'desc')
      expect(stub).to have_been_requested
    end
  end

  describe '#count' do
    it 'calls /search/count and returns body["count"]' do
      stub_request(:get, "#{base}/search/count")
        .with(query: hash_including('query' => 'type:ticket requester:a@b.com'))
        .to_return(status: 200, body: { 'count' => 42 }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect(client.count('ticket', query: 'requester:a@b.com')).to eq(42)
    end

    it 'raises APIError when the API errors out (no silent zero)' do
      stub_request(:get, "#{base}/search/count").with(query: hash_including({}))
                                                .to_return(status: 500, body: 'boom')

      expect { client.count('ticket', query: '') }
        .to raise_error(ForestAdminDatasourceZendesk::APIError, /count\(ticket\)/)
    end

    it 'returns 0 when the body has no count key (this is a real Zendesk response shape)' do
      stub_request(:get, "#{base}/search/count").with(query: hash_including({}))
                                                .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      expect(client.count('ticket', query: '')).to eq(0)
    end
  end

  describe '#find_ticket' do
    it 'fetches a single ticket by id' do
      stub_request(:get, "#{base}/tickets/123")
        .to_return(status: 200,
                   body: { 'ticket' => { 'id' => 123, 'subject' => 'Hi' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      ticket = client.find_ticket(123)
      expect(ticket.id).to eq(123)
      expect(ticket.subject).to eq('Hi')
    end

    it 'returns nil on 404' do
      stub_request(:get, "#{base}/tickets/999").to_return(status: 404, body: '{}')
      expect(client.find_ticket(999)).to be_nil
    end
  end

  describe '#find_user' do
    it 'fetches a single user by id' do
      stub_request(:get, "#{base}/users/7")
        .to_return(status: 200,
                   body: { 'user' => { 'id' => 7, 'email' => 'a@b.com' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect(client.find_user(7).email).to eq('a@b.com')
    end

    it 'returns nil on 404' do
      stub_request(:get, "#{base}/users/999").to_return(status: 404, body: '{}')
      expect(client.find_user(999)).to be_nil
    end
  end

  describe '#find_organization' do
    it 'fetches a single organization by id' do
      stub_request(:get, "#{base}/organizations/12")
        .to_return(status: 200,
                   body: { 'organization' => { 'id' => 12, 'name' => 'Acme' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect(client.find_organization(12).name).to eq('Acme')
    end
  end

  describe '#fetch_ticket_comments' do
    it 'returns the comments array' do
      stub_request(:get, "#{base}/tickets/42/comments")
        .to_return(status: 200,
                   body: { 'comments' => [{ 'id' => 1, 'body' => 'hi' }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      result = client.fetch_ticket_comments(42)
      expect(result).to eq([{ 'id' => 1, 'body' => 'hi' }])
    end

    it 'raises APIError on failure (no silent empty list)' do
      stub_request(:get, "#{base}/tickets/42/comments").to_return(status: 500, body: 'boom')
      expect { client.fetch_ticket_comments(42) }
        .to raise_error(ForestAdminDatasourceZendesk::APIError, /fetch_ticket_comments\(42\)/)
    end
  end

  describe '#fetch_user_emails' do
    it 'returns {} for empty input' do
      expect(client.fetch_user_emails([])).to eq({})
      expect(client.fetch_user_emails(nil)).to eq({})
      expect(WebMock).not_to have_requested(:any, /.*/)
    end

    it 'maps user ids to emails via /users/show_many' do
      stub_request(:get, "#{base}/users/show_many")
        .with(query: hash_including('ids' => '1,2,3'))
        .to_return(status: 200,
                   body: { 'users' => [
                     { 'id' => 1, 'email' => 'a@x.com' },
                     { 'id' => 2, 'email' => 'b@x.com' },
                     { 'id' => 3, 'email' => nil }
                   ] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect(client.fetch_user_emails([1, 2, 3])).to eq(1 => 'a@x.com', 2 => 'b@x.com', 3 => nil)
    end

    it 'batches ids in groups of 100' do
      ids = (1..150).to_a
      first  = stub_request(:get, "#{base}/users/show_many").with(query: hash_including('ids' => (1..100).to_a.join(',')))
                                                            .to_return(status: 200, body: { 'users' => [] }.to_json,
                                                                       headers: { 'Content-Type' => 'application/json' })
      second = stub_request(:get, "#{base}/users/show_many").with(query: hash_including('ids' => (101..150).to_a.join(',')))
                                                            .to_return(status: 200, body: { 'users' => [] }.to_json,
                                                                       headers: { 'Content-Type' => 'application/json' })
      client.fetch_user_emails(ids)
      expect(first).to have_been_requested
      expect(second).to have_been_requested
    end

    it 'returns {} if the bulk endpoint errors' do
      stub_request(:get, "#{base}/users/show_many").with(query: hash_including({}))
                                                   .to_return(status: 500, body: 'boom')
      expect(client.fetch_user_emails([1])).to eq({})
    end
  end

  describe '#fetch_users_by_ids' do
    it 'returns id -> full user hash' do
      stub_request(:get, "#{base}/users/show_many")
        .with(query: hash_including('ids' => '1,2'))
        .to_return(status: 200,
                   body: { 'users' => [
                     { 'id' => 1, 'email' => 'a@x.com', 'name' => 'A' },
                     { 'id' => 2, 'email' => 'b@x.com', 'name' => 'B' }
                   ] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      result = client.fetch_users_by_ids([1, 2])
      expect(result.keys).to eq([1, 2])
      expect(result[1]['name']).to eq('A')
    end

    it 'returns {} on error' do
      stub_request(:get, "#{base}/users/show_many").with(query: hash_including({}))
                                                   .to_return(status: 500, body: 'boom')
      expect(client.fetch_users_by_ids([1])).to eq({})
    end
  end

  describe '#fetch_organizations_by_ids' do
    it 'returns id -> organization hash' do
      stub_request(:get, "#{base}/organizations/show_many")
        .with(query: hash_including('ids' => '5'))
        .to_return(status: 200,
                   body: { 'organizations' => [{ 'id' => 5, 'name' => 'Acme' }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect(client.fetch_organizations_by_ids([5])[5]['name']).to eq('Acme')
    end
  end

  describe 'best-effort logging on degradation paths' do
    let(:logger) { instance_double(Logger, warn: nil) }

    before { ForestAdminDatasourceZendesk.logger = logger }
    after  { ForestAdminDatasourceZendesk.logger = nil }

    it 'logs a warning when fetch_user_emails fails and returns {}' do
      stub_request(:get, "#{base}/users/show_many").with(query: hash_including({}))
                                                   .to_return(status: 500, body: 'boom')

      expect(logger).to receive(:warn).with(/fetch_user_emails failed; degrading/)
      expect(client.fetch_user_emails([1])).to eq({})
    end

    it 'logs a warning when introspection fails at boot and returns []' do
      stub_request(:get, "#{base}/ticket_fields").to_return(status: 500, body: 'boom')

      expect(logger).to receive(:warn).with(/fetch_ticket_fields.*custom fields will be unavailable/)
      expect(client.fetch_ticket_fields).to eq([])
    end
  end

  describe 'schema introspection endpoints' do
    it 'fetches ticket_fields' do
      stub_request(:get, "#{base}/ticket_fields")
        .to_return(status: 200, body: { 'ticket_fields' => [{ 'id' => 1, 'type' => 'text' }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      expect(client.fetch_ticket_fields).to eq([{ 'id' => 1, 'type' => 'text' }])
    end

    it 'returns [] on error for ticket_fields' do
      stub_request(:get, "#{base}/ticket_fields").to_return(status: 500, body: 'boom')
      expect(client.fetch_ticket_fields).to eq([])
    end

    it 'fetches user_fields' do
      stub_request(:get, "#{base}/user_fields")
        .to_return(status: 200, body: { 'user_fields' => [{ 'key' => 'tier' }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      expect(client.fetch_user_fields).to eq([{ 'key' => 'tier' }])
    end

    it 'fetches organization_fields' do
      stub_request(:get, "#{base}/organization_fields")
        .to_return(status: 200, body: { 'organization_fields' => [{ 'key' => 'plan' }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      expect(client.fetch_organization_fields).to eq([{ 'key' => 'plan' }])
    end
  end
end
