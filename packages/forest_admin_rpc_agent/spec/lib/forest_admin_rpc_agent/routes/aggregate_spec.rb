require 'spec_helper'

module ForestAdminRpcAgent
  module Routes
    include ForestAdminDatasourceRpc
    describe Aggregate do
      include_context 'with caller'

      let(:route) { described_class.new }
      let(:collection_name) { 'users' }
      let(:aggregation_params) do
        { 'operation' => 'Sum', 'field' => 'amount', 'groups' => [{ field: 'country' }] }
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
      let(:filter) { ForestAdminDatasourceToolkit::Components::Query::Filter.new }
      let(:aggregation) do
        ForestAdminDatasourceToolkit::Components::Query::Aggregation.new(
          operation: aggregation_params['operation'],
          field: aggregation_params['field'],
          groups: aggregation_params['groups']
        )
      end
      let(:aggregate_result) { [{ 'group' => { 'country' => 'France' }, 'value' => 1000 }] }
      let(:response) { instance_double(Faraday::Response, success?: true, body: aggregate_result) }
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
            },
            country: {
              column_type: 'String',
              filter_operators: %w[in present equal],
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

        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(ForestAdminDatasourceCustomizer::Decorators::LazyJoin::LazyJoinCollectionDecorator)
          .to receive(:useless_join?)
          .and_return(false)
        # rubocop:enable RSpec/AnyInstance

        allow(ForestAdminDatasourceToolkit::Components::Query::FilterFactory)
          .to receive(:from_plain_object)
          .and_return(filter)
        allow(ForestAdminDatasourceToolkit::Components::Caller).to receive(:new).and_return(caller)

        allow(ForestAdminDatasourceToolkit::Components::Query::Aggregation)
          .to receive(:new)
          .and_return(aggregation)

        allow(Faraday).to receive(:new).and_return(faraday_connection)
        allow(faraday_connection).to receive(:send).and_return(response)
      end

      describe '#handle_request' do
        context 'when collection_name is provided' do
          it 'returns the aggregated data' do
            result = route.handle_request(params: params)
            expect(result).to eq(aggregate_result)
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
