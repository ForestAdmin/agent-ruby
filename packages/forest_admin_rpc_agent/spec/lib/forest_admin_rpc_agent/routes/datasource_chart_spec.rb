require 'spec_helper'
require 'faraday'

module ForestAdminRpcAgent
  module Routes
    include ForestAdminDatasourceRpc
    describe DatasourceChart do
      include_context 'with caller'

      let(:route) { described_class.new }
      let(:chart_name) { 'chart_revenue' }
      let(:params) do
        {
          'chart' => chart_name,
          'caller' => caller.to_h
        }
      end

      let(:chart_result) { { countCurrent: 500, countPrevious: 300 } }
      let(:response) { instance_double(Faraday::Response, success?: true, body: chart_result, status: 200) }
      let(:faraday_connection) { instance_double(Faraday::Connection) }

      before do
        @datasource = ForestAdminDatasourceRpc::Datasource.new(
          {},
          { collections: [], charts: [chart_name], rpc_relations: [] }
        )

        allow(ForestAdminRpcAgent::Facades::Container).to receive(:datasource).and_return(@datasource)
        allow(ForestAdminDatasourceToolkit::Components::Caller).to receive(:new).and_return(caller)
        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(ForestAdminDatasourceRpc::Datasource)
          .to receive(:render_chart)
          .and_return(chart_result)
        # rubocop:enable RSpec/AnyInstance
      end

      describe '#handle_request' do
        context 'when chart is provided' do
          it 'returns the chart data' do
            result = route.handle_request(params: params)
            expect(result).to eq(chart_result)
          end
        end

        context 'when chart is missing' do
          it 'returns an empty hash' do
            result = route.handle_request(params: {})
            expect(result).to eq({})
          end
        end
      end
    end
  end
end
