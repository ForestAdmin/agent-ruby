module ForestAdminDatasourceZendesk
  RSpec.describe Plugins::CloseTicket do
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

    it 'registers both solved and closed variants by default' do
      described_class.new.run(nil, collection_customizer,
                              datasource: datasource, ticket_id_field: 'last_zendesk_ticket_id')

      expect(collection_customizer.registered.keys).to contain_exactly(
        'Mark Zendesk ticket as solved', 'Mark selected Zendesk tickets as solved',
        'Mark Zendesk ticket as closed', 'Mark selected Zendesk tickets as closed'
      )
    end

    it 'honors :statuses to register a subset of variants' do
      described_class.new.run(nil, collection_customizer,
                              datasource: datasource, ticket_id_field: 'last_zendesk_ticket_id',
                              statuses: %w[solved])

      expect(collection_customizer.registered.keys).to contain_exactly(
        'Mark Zendesk ticket as solved', 'Mark selected Zendesk tickets as solved'
      )
    end

    it 'raises ArgumentError without :datasource' do
      expect { described_class.new.run(nil, collection_customizer, ticket_id_field: 'id') }
        .to raise_error(ArgumentError, /datasource/)
    end

    it 'raises ArgumentError without :ticket_id_field' do
      expect { described_class.new.run(nil, collection_customizer, datasource: datasource) }
        .to raise_error(ArgumentError, /ticket_id_field/)
    end

    it 'raises ArgumentError without a collection_customizer' do
      expect do
        described_class.new.run(nil, nil, datasource: datasource, ticket_id_field: 'id')
      end.to raise_error(ArgumentError, /collection/)
    end
  end
end
