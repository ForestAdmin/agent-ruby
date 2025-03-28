require 'spec_helper'

module ForestAdminRpcAgent
  module Routes
    describe List do
      include_context 'with caller'

      let(:route) { described_class.new }
      let(:collection_name) { 'users' }
      let(:filter_params) { { 'field' => 'email', 'operator' => 'equals', 'value' => 'test@example.com' } }
      let(:projection_params) { ['id', 'email'] }
      let(:params) do
        {
          'collection_name' => collection_name,
          'caller' => caller.to_h,
          'filter' => filter_params,
          'projection' => projection_params
        }
      end
      let(:datasource) { instance_double(Datasource) }
      let(:collection) { instance_double(Collection) }
      let(:projection) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Projection) }
      let(:filter) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter) }
      let(:list_result) { [{ id: 1, email: 'test@example.com' }] }

      before do
        allow(ForestAdminDatasourceToolkit::Components::Caller).to receive(:new).and_return(caller)
        allow(ForestAdminRpcAgent::Facades::Container).to receive(:datasource).and_return(datasource)
        allow(datasource).to receive(:get_collection).with(collection_name).and_return(collection)

        allow(ForestAdminDatasourceToolkit::Components::Query::Projection).to receive(:new)
          .with(projection_params)
          .and_return(projection)

        allow(ForestAdminDatasourceToolkit::Components::Query::FilterFactory).to receive(:from_plain_object)
          .with(filter_params)
          .and_return(filter)

        allow(collection).to receive(:list).with(caller, filter, projection).and_return(list_result)
      end

      describe '#handle_request' do
        context 'when collection_name is provided' do
          it 'returns the list of items as JSON' do
            result = route.handle_request(params: params)
            expect(result).to eq(list_result.to_json)
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
