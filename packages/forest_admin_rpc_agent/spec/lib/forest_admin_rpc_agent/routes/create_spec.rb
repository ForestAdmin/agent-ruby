require 'spec_helper'

module ForestAdminRpcAgent
  module Routes
    include ForestAdminDatasourceRpc
    describe Create do
      include_context 'with caller'

      let(:route) { described_class.new }
      let(:collection_name) { 'users' }
      let(:data) { { 'email' => 'test@example.com', 'name' => 'John Doe' } }
      let(:create_result) { [{ 'id' => 1, 'email' => 'test@example.com', 'name' => 'John Doe' }] }

      let(:params) do
        {
          'collection_name' => collection_name,
          'caller' => caller.to_h,
          'data' => data
        }
      end
      let(:response) { instance_double(Faraday::Response, success?: true, body: create_result) }
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
              filter_operators: %w[in present i_contains contains equal],
              is_primary_key: false,
              is_read_only: false,
              is_sortable: true,
              default_value: nil,
              enum_values: [],
              validation: [],
              type: 'Column'
            },
            name: {
              column_type: 'String',
              filter_operators: %w[in present i_contains contains equal],
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
        allow_any_instance_of(ForestAdminDatasourceCustomizer::Decorators::Binary::BinaryCollectionDecorator)
          .to receive(:convert_value).and_wrap_original do |m, to_backend, path, value|
          m.call(to_backend, path.to_s, value)
        end
        # rubocop:enable RSpec/AnyInstance

        allow(ForestAdminDatasourceToolkit::Components::Caller).to receive(:new).and_return(caller)
        allow(Faraday).to receive(:new).and_return(faraday_connection)
        allow(faraday_connection).to receive(:send).and_return(response)
      end

      describe '#handle_request' do
        context 'when collection_name is provided' do
          it 'creates a new record and returns it' do
            result = route.handle_request(params: params)
            expect(result).to eq(create_result)
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
