require 'spec_helper'
require 'json'

module ForestAdminRpcAgent
  module Routes
    include ForestAdminDatasourceRpc
    include ForestAdminDatasourceToolkit::Components::Query
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    describe ActionExecute do
      include_context 'with caller'
      subject(:route) { described_class.new }
      let(:collection_name) { 'users' }
      let(:filter) { ForestAdminDatasourceToolkit::Components::Query::Filter.new }
      let(:params) do
        {
          'collection_name' => 'users',
          'caller' => caller.to_h,
          'filter' => {},
          'data' => { 'field' => 'value' },
          'action' => 'some_action'
        }
      end
      let(:args) { { params: params } }
      let(:expected_response) { { success: true }.to_json }
      let(:response) { instance_double(Faraday::Response, success?: true, body: expected_response) }
      let(:faraday_connection) { instance_double(Faraday::Connection) }

      before do
        collection_schema = {
          name: collection_name,
          fields: {
            id: {
              column_type: 'Number',
              filter_operators: %w[present greater_than],
              is_primary_key: true,
              is_read_only: false,
              is_sortable: true,
              default_value: nil,
              enum_values: [],
              validations: [],
              type: 'Column'
            },
            email: {
              column_type: 'String',
              filter_operators: %w[in present i_contains contains],
              is_primary_key: false,
              is_read_only: false,
              is_sortable: true,
              default_value: nil,
              enum_values: [],
              validations: [],
              type: 'Column'
            }
          },
          countable: true,
          searchable: true,
          charts: [],
          segments: [],
          actions: {}
        }
        @datasource = ForestAdminDatasourceRpc::Datasource.new(
          {},
          { collections: [collection_schema], charts: [], rpc_relations: [] }
        )
        ForestAdminRpcAgent::Agent.instance.add_datasource(@datasource)
        ForestAdminRpcAgent::Agent.instance.build

        allow(ForestAdminDatasourceToolkit::Components::Query::FilterFactory)
          .to receive(:from_plain_object)
          .and_return(filter)
        allow(ForestAdminDatasourceToolkit::Components::Caller).to receive(:new).and_return(caller)

        allow(Faraday::Connection).to receive(:new).and_return(faraday_connection)
        allow(faraday_connection).to receive_messages(get: response, post: response)
      end

      describe '#handle_request' do
        context 'when collection_name is provided' do
          it 'executes the action on the collection and returns the response' do
            response = route.handle_request(args)
            expect(response).to eq(expected_response.to_json)
          end
        end

        context 'when collection_name is missing' do
          let(:params) { {} }

          it 'returns an empty JSON object' do
            response = route.handle_request(args)
            expect(response).to eq('{}')
          end
        end
      end
    end
  end
end
