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
          'name' => chart_name,
          'record_id' => record_id
        }
      end

      let(:datasource) { instance_double(ForestAdminDatasourceRpc::Datasource) }
      let(:collection) { instance_double(ForestAdminDatasourceRpc::Collection) }
      let(:chart_result) { { countCurrent: 10, countPrevious: nil } }

      before do
        allow(ForestAdminDatasourceToolkit::Components::Caller).to receive(:new).and_return(caller)
        allow(ForestAdminRpcAgent::Facades::Container).to receive(:datasource).and_return(datasource)
        allow(datasource).to receive(:get_collection).with(collection_name).and_return(collection)

        allow(ForestAdminAgent::Utils::Id).to receive(:unpack_id)
          .with(collection, record_id)
          .and_return(unpacked_id)

        allow(collection).to receive(:render_chart)
          .with(caller, chart_name, unpacked_id)
          .and_return(chart_result)
      end

      describe '#handle_request' do
        context 'when collection_name and chart_name are provided' do
          it 'returns the chart data' do
            result = route.handle_request(params: params)
            expect(result).to eq(chart_result)
          end
        end

        context 'when collection_name is missing' do
          it 'returns an empty JSON object' do
            result = route.handle_request(params: {})
            expect(result).to eq('{}')
          end
        end
      end
    end
  end
end
