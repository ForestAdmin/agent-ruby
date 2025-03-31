require 'spec_helper'

module ForestAdminRpcAgent
  module Routes
    include ForestAdminDatasourceRpc
    describe Delete do
      include_context 'with caller'

      let(:route) { described_class.new }
      let(:collection_name) { 'users' }
      let(:filter_params) { { 'field' => 'id', 'operator' => 'equals', 'value' => 1 } }
      let(:params) do
        {
          'collection_name' => collection_name,
          'caller' => caller.to_h,
          'filter' => filter_params
        }
      end
      let(:datasource) { instance_double(Datasource) }
      let(:collection) { instance_double(Collection) }
      let(:filter) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter) }
      let(:delete_result) { nil }

      before do
        allow(ForestAdminDatasourceToolkit::Components::Caller).to receive(:new).and_return(caller)
        allow(ForestAdminRpcAgent::Facades::Container).to receive(:datasource).and_return(datasource)
        allow(datasource).to receive(:get_collection).with(collection_name).and_return(collection)

        allow(ForestAdminDatasourceToolkit::Components::Query::FilterFactory).to receive(:from_plain_object)
          .with(filter_params)
          .and_return(filter)

        allow(collection).to receive(:delete).with(caller, filter).and_return(delete_result)
      end

      describe '#handle_request' do
        context 'when collection_name is provided' do
          it 'deletes the items and returns the result as JSON' do
            result = route.handle_request(params: params)
            expect(result).to eq(delete_result.to_json)
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
