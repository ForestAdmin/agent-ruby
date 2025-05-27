require 'spec_helper'

module ForestAdminRpcAgent
  module Routes
    include ForestAdminDatasourceRpc
    describe Aggregate do
      include_context 'with caller'

      let(:route) { described_class.new }
      let(:collection_name) { 'users' }
      let(:aggregation_params) do
        { 'operation' => 'Sum', 'field' => 'amount', 'groups' => ['country'] }
      end
      let(:filter_params) { { 'field' => 'country', 'operator' => 'equal', 'value' => 'France' } }
      let(:params) do
        {
          'collection_name' => collection_name,
          'caller' => caller.to_h,
          'aggregation' => aggregation_params,
          'filter' => filter_params,
          'limit' => 10
        }
      end

      let(:datasource) { instance_double(Datasource) }
      let(:collection) { instance_double(Collection) }
      let(:aggregation) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Aggregation) }
      let(:filter) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter) }
      let(:aggregate_result) { [{ 'country' => 'France', 'total_amount' => 1000 }] }

      before do
        allow(ForestAdminDatasourceToolkit::Components::Caller).to receive(:new).and_return(caller)
        allow(ForestAdminRpcAgent::Facades::Container).to receive(:datasource).and_return(datasource)
        allow(datasource).to receive(:get_collection).with(collection_name).and_return(collection)

        allow(ForestAdminDatasourceToolkit::Components::Query::Aggregation).to receive(:new)
          .with(
            operation: aggregation_params['operation'],
            field: aggregation_params['field'],
            groups: aggregation_params['groups']
          ).and_return(aggregation)

        allow(ForestAdminDatasourceToolkit::Components::Query::FilterFactory).to receive(:from_plain_object)
          .with(filter_params)
          .and_return(filter)

        allow(collection).to receive(:aggregate).with(caller, filter, aggregation,
                                                      params['limit']).and_return(aggregate_result)
      end

      describe '#handle_request' do
        context 'when collection_name is provided' do
          it 'returns the aggregated data as JSON' do
            result = route.handle_request(params: params)
            expect(result).to eq(aggregate_result.to_json)
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
