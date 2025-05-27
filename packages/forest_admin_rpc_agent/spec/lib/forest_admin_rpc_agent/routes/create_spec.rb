require 'spec_helper'

module ForestAdminRpcAgent
  module Routes
    include ForestAdminDatasourceRpc
    describe Create do
      include_context 'with caller'

      let(:route) { described_class.new }
      let(:collection_name) { 'users' }
      let(:data) { { 'email' => 'test@example.com', 'name' => 'John Doe' } }
      let(:params) do
        {
          'collection_name' => collection_name,
          'caller' => caller.to_h,
          'data' => data
        }
      end
      let(:datasource) { instance_double(ForestAdminDatasourceRpc::Datasource) }
      let(:collection) { instance_double(Collection) }
      let(:create_result) { { id: 1, email: 'test@example.com', name: 'John Doe' } }

      before do
        allow(ForestAdminDatasourceToolkit::Components::Caller).to receive(:new).and_return(caller)
        allow(ForestAdminRpcAgent::Facades::Container).to receive(:datasource).and_return(datasource)
        allow(datasource).to receive(:get_collection).with(collection_name).and_return(collection)
        allow(collection).to receive(:create).with(caller, data).and_return(create_result)
      end

      describe '#handle_request' do
        context 'when collection_name is provided' do
          it 'creates a new record and returns it as JSON' do
            result = route.handle_request(params: params)
            expect(result).to eq(create_result.to_json)
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
