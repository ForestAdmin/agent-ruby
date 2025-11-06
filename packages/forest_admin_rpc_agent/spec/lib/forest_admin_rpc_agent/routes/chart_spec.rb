require 'spec_helper'

module ForestAdminRpcAgent
  module Routes
    include ForestAdminDatasourceRpc
    describe Chart do
      include_context 'with caller'

      let(:route) { described_class.new }
      let(:collection_name) { 'users' }
      let(:chart_name) { 'value_chart' }
      let(:record_id) { '123' }
      let(:unpacked_id) { 123 }
      let(:params) do
        {
          'collection_name' => collection_name,
          'caller' => caller.to_h,
          'chart' => chart_name,
          'record_id' => record_id
        }
      end

      let(:chart_result) { { countCurrent: 10, countPrevious: nil } }
      let(:response) { instance_double(Faraday::Response, success?: true, body: chart_result) }
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
        allow(Faraday).to receive(:new).and_return(faraday_connection)
        allow(faraday_connection).to receive(:send).and_return(response)
      end

      describe '#handle_request' do
        context 'when collection_name and chart_name are provided' do
          it 'returns the chart data' do
            result = route.handle_request(params: params)
            expect(result).to eq(chart_result)
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
