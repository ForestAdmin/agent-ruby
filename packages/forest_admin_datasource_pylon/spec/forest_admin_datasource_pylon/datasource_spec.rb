RSpec.describe ForestAdminDatasourcePylon::Datasource do
  let(:datasource) { described_class.new(api_key: 'k') }
  let(:base) { ForestAdminDatasourcePylon::Configuration::DEFAULT_BASE_URL }

  before { stub_custom_fields }

  def definition(slug, type: 'text')
    { 'id' => "cf_#{slug}", 'slug' => slug, 'label' => slug.capitalize, 'type' => type }
  end

  it 'builds a configuration from the api key' do
    expect(datasource.configuration.api_key).to eq('k')
    expect(datasource.configuration.url).to eq(ForestAdminDatasourcePylon::Configuration::DEFAULT_BASE_URL)
  end

  it 'forwards the remaining options to the configuration' do
    stub_custom_fields(base: 'https://pylon.test')
    custom = described_class.new(api_key: 'k', base_url: 'https://pylon.test/', timeout: 3)

    expect(custom.configuration.url).to eq('https://pylon.test')
    expect(custom.configuration.timeout).to eq(3)
  end

  it 'exposes a client built on that configuration' do
    expect(datasource.client).to be_a(ForestAdminDatasourcePylon::Client)
  end

  it 'registers the five collections Pylon exposes' do
    expect(datasource.collections.keys)
      .to eq(%w[PylonIssue PylonAccount PylonContact PylonUser PylonTeam])
    expect(datasource.get_collection('PylonIssue')).to be_a(ForestAdminDatasourcePylon::Collections::Issue)
    expect(datasource.get_collection('PylonAccount')).to be_a(ForestAdminDatasourcePylon::Collections::Account)
    expect(datasource.get_collection('PylonContact')).to be_a(ForestAdminDatasourcePylon::Collections::Contact)
    expect(datasource.get_collection('PylonUser')).to be_a(ForestAdminDatasourcePylon::Collections::User)
    expect(datasource.get_collection('PylonTeam')).to be_a(ForestAdminDatasourcePylon::Collections::Team)
  end

  # Every relation declared by one of them points at another: a foreign
  # collection left unregistered is a schema the agent refuses to boot on.
  it 'registers a collection for every foreign collection its relations point at' do
    relations = datasource.collections.values.flat_map do |collection|
      collection.fields.values.reject { |field| field.type == 'Column' }
    end

    expect(relations).not_to be_empty
    expect(relations.map(&:foreign_collection).uniq - datasource.collections.keys).to be_empty
  end

  it 'refuses to build without an api key' do
    expect { described_class.new(api_key: nil) }.to raise_error(ForestAdminDatasourcePylon::ConfigurationError)
  end

  describe 'custom fields' do
    # Pylon indexes its definitions by object type and asks for one on every
    # call, so the three collections carrying custom fields cost one call each.
    it 'reads the definitions of the three object types Pylon carries them on' do
      datasource

      %w[issue account contact].each do |object_type|
        expect(WebMock).to have_requested(:get, "#{base}/custom-fields")
          .with(query: { 'object_type' => object_type }).once
      end
    end

    # A definition is a column of the collection it was declared on, and of no
    # other: Pylon scopes a custom field to one object type.
    it 'adds each definition to the collection its object type registers' do
      stub_custom_fields(issue: [definition('severity')], account: [definition('tier')],
                         contact: [definition('nps', type: 'number')])

      expect(datasource.get_collection('PylonIssue').fields).to have_key('severity')
      expect(datasource.get_collection('PylonAccount').fields).to have_key('tier')
      expect(datasource.get_collection('PylonContact').fields['nps'].column_type).to eq('Number')
      expect(datasource.get_collection('PylonIssue').fields).not_to have_key('tier')
    end

    # Users and teams have no custom field at all in Pylon, so nothing is asked
    # for them -- an absent call rather than one answering an empty list.
    it 'asks for no definition on users and teams' do
      datasource

      %w[user team].each do |object_type|
        expect(WebMock).not_to have_requested(:get, "#{base}/custom-fields")
          .with(query: { 'object_type' => object_type })
      end
    end

    # The definitions are read while the agent boots: a Pylon that is down, or a
    # token without the permission, has to cost the operator the custom columns
    # rather than the agent.
    it 'boots on the native schema when the definitions cannot be read' do
      stub_request(:get, "#{base}/custom-fields").to_return(status: 500, body: '{}',
                                                            headers: { 'Content-Type' => 'application/json' })

      expect { datasource }.not_to raise_error
      expect(datasource.collections.keys).to include('PylonIssue')
      expect(datasource.get_collection('PylonIssue').custom_fields).to eq([])
    end

    # A custom field is filtered through the very slug it is read by, so nothing
    # is held datasource-wide -- and two Pylon organizations in the same agent
    # cannot end up advertising each other's columns.
    it 'keeps the custom fields of one datasource out of another' do
      stub_custom_fields(issue: [definition('severity')])
      first = described_class.new(api_key: 'k')

      stub_custom_fields(issue: [definition('tier')])
      second = described_class.new(api_key: 'k')

      expect(first.get_collection('PylonIssue').fields).to have_key('severity')
      expect(first.get_collection('PylonIssue').fields).not_to have_key('tier')
      expect(second.get_collection('PylonIssue').fields).to have_key('tier')
      expect(second.get_collection('PylonIssue').fields).not_to have_key('severity')
    end

    # Registration evaluates the collision against the final native schema, so a
    # slug shadowing a column the collection already declares is left out.
    it 'skips a definition colliding with a native column' do
      allow(ForestAdminDatasourcePylon.logger).to receive(:warn)
      stub_custom_fields(issue: [definition('title')])

      expect(datasource.get_collection('PylonIssue').custom_fields).to eq([])
      expect(datasource.get_collection('PylonIssue').fields['title'].filter_operators).not_to be_empty
      expect(ForestAdminDatasourcePylon.logger)
        .to have_received(:warn).with(/'title' on collection 'PylonIssue' conflicts/)
    end
  end
end
