module ForestAdminDatasourceZendesk
  RSpec.describe Plugins::CreateTicketWithNotification do
    let(:client) { instance_double(ForestAdminDatasourceZendesk::Client) }
    let(:datasource) do
      instance_double(ForestAdminDatasourceZendesk::Datasource, client: client, custom_field_mapping: {})
    end
    let(:collection_customizer) do
      Class.new do
        attr_reader :registered

        def initialize = @registered = {}
        def add_action(name, action) = @registered[name] = action
      end.new
    end

    it 'delegates registration to Actions::CreateTicketWithNotification.register_on' do
      described_class.new.run(nil, collection_customizer,
                              datasource: datasource,
                              default_subject: 'Welcome',
                              ticket_id_field: 'last_zendesk_ticket_id')

      expect(collection_customizer.registered).to have_key(Actions::CreateTicketWithNotification::NAME)
      action = collection_customizer.registered[Actions::CreateTicketWithNotification::NAME]
      expect(action.form.find { |f| f[:label] == 'Subject' }[:default_value]).to eq('Welcome')
    end

    it 'honors :action_name from options' do
      described_class.new.run(nil, collection_customizer,
                              datasource: datasource, action_name: 'Open ticket')

      expect(collection_customizer.registered.keys).to contain_exactly('Open ticket')
    end

    it 'raises ArgumentError without :datasource' do
      expect { described_class.new.run(nil, collection_customizer, {}) }
        .to raise_error(ArgumentError, /datasource/)
    end

    it 'raises ArgumentError without a collection_customizer' do
      expect { described_class.new.run(nil, nil, datasource: datasource) }
        .to raise_error(ArgumentError, /collection/)
    end
  end
end
