RSpec.describe ForestAdminDatasourceZendesk::Datasource do
  let(:valid_args) { { subdomain: 'acme', username: 'agent@acme.com/token', token: 'secret' } }
  let(:base) { 'https://acme.zendesk.com/api/v2' }

  before do
    # Stub all introspection endpoints with empty responses (no custom fields).
    %w[ticket_fields user_fields organization_fields].each do |path|
      stub_request(:get, "#{base}/#{path}")
        .to_return(status: 200, body: { path => [] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end
  end

  it 'builds with valid credentials' do
    ds = described_class.new(**valid_args)
    expect(ds.configuration.subdomain).to eq('acme')
    expect(ds.client).to be_a(ForestAdminDatasourceZendesk::Client)
  end

  it 'raises ConfigurationError when credentials are missing' do
    expect { described_class.new(subdomain: nil, username: '', token: nil) }
      .to raise_error(ForestAdminDatasourceZendesk::ConfigurationError)
  end

  it 'registers the three Zendesk collections' do
    ds = described_class.new(**valid_args)
    expect(ds.collections.keys).to contain_exactly(
      'ZendeskTicket', 'ZendeskUser', 'ZendeskOrganization'
    )
  end

  it 'forwards discovered ticket custom fields into the Ticket schema' do
    stub_request(:get, "#{base}/ticket_fields")
      .to_return(status: 200,
                 body: { 'ticket_fields' => [
                   { 'id' => 7700, 'type' => 'text', 'active' => true, 'removable' => true, 'title' => 'Tier' }
                 ] }.to_json,
                 headers: { 'Content-Type' => 'application/json' })

    ds = described_class.new(**valid_args)
    expect(ds.get_collection('ZendeskTicket').schema[:fields]).to have_key('custom_7700')
  end

  it 'exposes the ticket custom field mapping on the datasource instance' do
    stub_request(:get, "#{base}/ticket_fields")
      .to_return(status: 200,
                 body: { 'ticket_fields' => [
                   { 'id' => 7700, 'type' => 'text', 'active' => true, 'removable' => true, 'title' => 'Tier' }
                 ] }.to_json,
                 headers: { 'Content-Type' => 'application/json' })

    ds = described_class.new(**valid_args)
    expect(ds.custom_field_mapping['custom_7700']).to eq('custom_field_7700')
  end

  it 'maps keyed user custom fields to their Zendesk Search key' do
    stub_request(:get, "#{base}/user_fields")
      .to_return(status: 200,
                 body: { 'user_fields' => [
                   { 'id' => 1, 'key' => 'tier', 'type' => 'text', 'active' => true }
                 ] }.to_json,
                 headers: { 'Content-Type' => 'application/json' })

    ds = described_class.new(**valid_args)
    expect(ds.custom_field_mapping['tier']).to eq('tier')
  end

  it 'defaults action templates to nil and close actions to none when no kwargs are supplied' do
    ds = described_class.new(**valid_args)
    expect(ds.default_ticket_subject).to be_nil
    expect(ds.default_ticket_message).to be_nil
    expect(ds.requester_email_default).to be_nil
    expect(ds.close_ticket_statuses).to eq([])
  end

  it 'stores configured action defaults verbatim for the smart action to consume' do
    ds = described_class.new(**valid_args,
                             default_ticket_subject: 'Welcome {{record.name}}',
                             default_ticket_message: '<p>Hi {{record.name}}</p>',
                             requester_email_default: 'support@example.com',
                             close_ticket_statuses: %w[solved closed])
    expect(ds.default_ticket_subject).to eq('Welcome {{record.name}}')
    expect(ds.default_ticket_message).to eq('<p>Hi {{record.name}}</p>')
    expect(ds.requester_email_default).to eq('support@example.com')
    expect(ds.close_ticket_statuses).to eq(%w[solved closed])
  end

  it 'normalizes close_ticket_statuses entries to strings' do
    ds = described_class.new(**valid_args, close_ticket_statuses: %i[solved closed])
    expect(ds.close_ticket_statuses).to eq(%w[solved closed])
  end

  it 'opts in CloseTicket variants on the Ticket schema when close_ticket_statuses is set' do
    ds = described_class.new(**valid_args, close_ticket_statuses: %w[closed])
    actions = ds.get_collection('ZendeskTicket').schema[:actions].keys
    expect(actions).to include('Mark as closed', 'Mark selected as closed')
    expect(actions).not_to include('Mark as solved', 'Mark selected as solved')
  end

  it 'isolates custom field mappings between two datasource instances' do
    # Multi-tenancy: each datasource owns its own mapping.
    stub_request(:get, "#{base}/ticket_fields")
      .to_return(status: 200,
                 body: { 'ticket_fields' => [
                   { 'id' => 1111, 'type' => 'text', 'active' => true, 'removable' => true }
                 ] }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    other_base = 'https://beta.zendesk.com/api/v2'
    %w[ticket_fields user_fields organization_fields].each do |path|
      stub_request(:get, "#{other_base}/#{path}")
        .to_return(status: 200, body: { path => [] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    a = described_class.new(**valid_args)
    b = described_class.new(subdomain: 'beta', username: 'x@x/token', token: 't')

    expect(a.custom_field_mapping).to have_key('custom_1111')
    expect(b.custom_field_mapping).not_to have_key('custom_1111')
  end
end
