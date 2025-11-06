require 'spec_helper'

module ForestAdminRpcAgent
  module Routes
    include ForestAdminDatasourceRpc
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    describe Update do
      include_context 'with caller'

      let(:route) { described_class.new }
      let(:collection_name) { 'users' }
      let(:filter_params) { { 'field' => 'id', 'operator' => 'equals', 'value' => 1 } }
      let(:update_data) { { 'email' => 'updated@example.com' } }
      let(:params) do
        {
          'collection_name' => collection_name,
          'caller' => caller.to_h,
          'filter' => filter_params,
          'data' => update_data
        }
      end
      let(:filter) { ForestAdminDatasourceToolkit::Components::Query::Filter.new }
      let(:update_result) { nil }
      let(:response) { instance_double(Faraday::Response, success?: true, body: {}) }
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
              validation: [],
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
              validation: [],
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

        allow(ForestAdminDatasourceToolkit::Components::Caller).to receive(:new).and_return(caller)
        allow(ForestAdminDatasourceToolkit::Components::Query::FilterFactory)
          .to receive(:from_plain_object)
          .and_return(filter)

        allow(Faraday::Connection).to receive(:new).and_return(faraday_connection)
        allow(faraday_connection).to receive_messages(get: response, post: response)
      end

      describe '#handle_request' do
        context 'when collection_name is provided' do
          it 'updates the collection and returns the result as JSON' do
            result = route.handle_request(params: params)
            expect(result).to eq([])
          end
        end

        context 'when collection_name is missing' do
          it 'returns an empty hash' do
            result = route.handle_request(params: {})
            expect(result).to eq({})
          end
        end
      end
    end
  end
end
