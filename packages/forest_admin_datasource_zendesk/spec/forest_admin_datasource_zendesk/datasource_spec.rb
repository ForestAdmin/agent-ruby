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

  it 'registers the four Zendesk collections' do
    ds = described_class.new(**valid_args)
    expect(ds.collections.keys).to contain_exactly(
      'ZendeskTicket', 'ZendeskUser', 'ZendeskOrganization', 'ZendeskComment'
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

  it 'populates the translator custom_field_mapping for ticket custom fields' do
    stub_request(:get, "#{base}/ticket_fields")
      .to_return(status: 200,
                 body: { 'ticket_fields' => [
                   { 'id' => 7700, 'type' => 'text', 'active' => true, 'removable' => true, 'title' => 'Tier' }
                 ] }.to_json,
                 headers: { 'Content-Type' => 'application/json' })

    described_class.new(**valid_args)
    mapping = ForestAdminDatasourceZendesk::Query::ConditionTreeTranslator.custom_field_mapping
    expect(mapping['custom_7700']).to eq('custom_field_7700')
  end

  it 'maps keyed user custom fields to their Zendesk Search key' do
    stub_request(:get, "#{base}/user_fields")
      .to_return(status: 200,
                 body: { 'user_fields' => [
                   { 'id' => 1, 'key' => 'tier', 'type' => 'text', 'active' => true }
                 ] }.to_json,
                 headers: { 'Content-Type' => 'application/json' })

    described_class.new(**valid_args)
    mapping = ForestAdminDatasourceZendesk::Query::ConditionTreeTranslator.custom_field_mapping
    expect(mapping['tier']).to eq('tier')
  end
end
