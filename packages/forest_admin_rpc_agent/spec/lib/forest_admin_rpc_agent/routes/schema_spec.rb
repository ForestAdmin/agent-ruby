require 'spec_helper'

module ForestAdminRpcAgent
  module Routes
    include ForestAdminDatasourceRpc
    describe Schema do
      let(:route) { described_class.new }
      let(:agent) { instance_double(ForestAdminRpcAgent::Agent) }
      let(:customizer) { instance_double(ForestAdminDatasourceCustomizer::DatasourceCustomizer) }
      let(:datasource) { instance_double(ForestAdminDatasourceRpc::Datasource) }
      let(:logger) { instance_double(Logger) }

      let(:collection_user) { instance_double(Collection, name: 'users', schema: { fields: ['id', 'email'] }) }
      let(:collection_order) { instance_double(Collection, name: 'orders', schema: { fields: ['id', 'total'] }) }
      let(:collections) { { 'users' => collection_user, 'orders' => collection_order } }
      let(:schema) { { some_key: 'some_value' } }
      let(:datasource_with_connections) do
        instance_double(ForestAdminDatasourceToolkit::Datasource, live_query_connections: { 'primary' => 'primary' })
      end
      let(:expected_schema) do
        {
          some_key: 'some_value',
          collections: [
            { fields: ['id', 'total'], name: 'orders' },
            { fields: ['id', 'email'], name: 'users' }
          ],
          native_query_connections: [
            { name: 'primary' }
          ]
        }.to_json
      end

      before do
        allow(ForestAdminRpcAgent::Agent).to receive(:instance).and_return(agent)
        allow(agent).to receive(:customizer).and_return(customizer)
        allow(ForestAdminRpcAgent::Facades::Container).to receive(:logger).and_return(logger)
        allow(customizer).to receive_messages(
          schema: schema,
          datasource: datasource,
          datasources: [datasource_with_connections]
        )
        allow(datasource).to receive_messages(
          collections: collections,
          live_query_connections: { 'primary' => 'primary' }
        )
      end

      describe '#handle_request' do
        it 'returns the schema with sorted collections as JSON' do
          result = route.handle_request({})
          expect(result).to eq(expected_schema)
        end
      end
    end
  end
end
