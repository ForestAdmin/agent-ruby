require 'spec_helper'
require 'faraday'

module ForestAdminRpcAgent
  module Routes
    include ForestAdminDatasourceRpc

    describe NativeQuery do
      let(:route) { described_class.new }
      let(:connection_name) { 'primary' }
      let(:query) { 'SELECT * FROM users WHERE id = ?' }
      let(:binds) { [1] }
      let(:params) do
        {
          'connection_name' => connection_name,
          'query' => query,
          'binds' => binds
        }
      end

      let(:query_result) { [{ 'id' => 1, 'name' => 'John Doe' }] }
      let(:datasource) { instance_double(ForestAdminDatasourceToolkit::Datasource) }

      before do
        allow(ForestAdminRpcAgent::Facades::Container).to receive(:datasource).and_return(datasource)
        allow(datasource).to receive(:execute_native_query).and_return(query_result)
      end

      describe '#handle_request' do
        context 'when connection_name and query are provided' do
          it 'executes the native query and returns the result' do
            result = route.handle_request(params: params)
            expect(result).to eq(query_result.to_json)
            expect(datasource).to have_received(:execute_native_query).with(connection_name, query, binds)
          end
        end

        context 'when binds is not provided' do
          it 'defaults to empty array' do
            params_without_binds = params.except('binds')
            route.handle_request(params: params_without_binds)
            expect(datasource).to have_received(:execute_native_query).with(connection_name, query, [])
          end
        end

        context 'when connection_name is missing' do
          it 'returns an empty JSON object' do
            result = route.handle_request(params: { 'query' => query })
            expect(result).to eq('{}')
            expect(datasource).not_to have_received(:execute_native_query)
          end
        end

        context 'when query is missing' do
          it 'returns an empty JSON object' do
            result = route.handle_request(params: { 'connection_name' => connection_name })
            expect(result).to eq('{}')
            expect(datasource).not_to have_received(:execute_native_query)
          end
        end
      end
    end
  end
end
