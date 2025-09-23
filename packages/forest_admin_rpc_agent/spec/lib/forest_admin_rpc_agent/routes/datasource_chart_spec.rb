require 'spec_helper'

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

      let(:datasource) { instance_double(ForestAdminDatasourceRpc::Datasource) }
      let(:chart_result) { { countCurrent: 500, countPrevious: 300 } }

      before do
        allow(ForestAdminDatasourceToolkit::Components::Caller).to receive(:new).and_return(caller)
        allow(ForestAdminRpcAgent::Facades::Container).to receive(:datasource).and_return(datasource)
        allow(datasource).to receive(:render_chart).with(caller, chart_name).and_return(chart_result)
      end

      describe '#handle_request' do
        context 'when chart is provided' do
          it 'returns the chart data' do
            result = route.handle_request(params: params)
            expect(result).to eq(chart_result.to_json)
          end
        end

        context 'when chart is missing' do
          it 'returns an empty JSON object' do
            result = route.handle_request(params: {})
            expect(result).to eq('{}')
          end
        end
      end
    end
  end
end
