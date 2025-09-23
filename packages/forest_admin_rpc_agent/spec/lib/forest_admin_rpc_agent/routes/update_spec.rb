require 'spec_helper'

module ForestAdminRpcAgent
  module Routes
    include ForestAdminDatasourceRpc
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
      let(:datasource) { instance_double(ForestAdminDatasourceRpc::Datasource) }
      let(:collection) { instance_double(ForestAdminDatasourceRpc::Collection) }
      let(:filter) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter) }
      let(:update_result) { nil }

      before do
        RSpec::Mocks.space.reset_all
        allow(ForestAdminDatasourceToolkit::Components::Caller).to receive(:new).and_return(caller)
        allow(ForestAdminRpcAgent::Facades::Container).to receive(:datasource).and_return(datasource)
        allow(datasource).to receive(:get_collection).with(collection_name).and_return(collection)

        allow(ForestAdminDatasourceToolkit::Components::Query::FilterFactory).to receive(:from_plain_object)
          .with(filter_params)
          .and_return(filter)

        allow(collection).to receive(:update).with(caller, filter, update_data).and_return(update_result)
      end

      describe '#handle_request' do
        context 'when collection_name is provided' do
          it 'updates the collection and returns the result as JSON' do
            result = route.handle_request(params: params)
            expect(result).to eq(update_result.to_json)
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
