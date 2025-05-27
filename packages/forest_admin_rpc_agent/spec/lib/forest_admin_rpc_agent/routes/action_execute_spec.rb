require 'spec_helper'
require 'json'

module ForestAdminRpcAgent
  module Routes
    include ForestAdminDatasourceRpc
    include ForestAdminDatasourceToolkit::Components::Query
    describe ActionExecute do
      include_context 'with caller'
      subject(:route) { described_class.new }

      let(:datasource) { instance_double(Datasource) }
      let(:collection) { instance_double(Collection) }
      let(:filter) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter) }
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

      before do
        allow(ForestAdminRpcAgent::Facades::Container).to receive(:datasource).and_return(datasource)
        allow(datasource).to receive(:get_collection).with('users').and_return(collection)
        allow(FilterFactory).to receive(:from_plain_object).with({}).and_return(filter)
        allow(ForestAdminDatasourceToolkit::Components::Caller).to receive(:new).and_return(caller)
        allow(collection).to receive(:execute).with(caller, 'some_action', { 'field' => 'value' },
                                                    filter).and_return(expected_response)
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
