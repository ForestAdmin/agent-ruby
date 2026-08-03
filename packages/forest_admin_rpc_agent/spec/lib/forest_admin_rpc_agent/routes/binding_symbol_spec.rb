require 'spec_helper'
require 'faraday'

module ForestAdminRpcAgent
  module Routes
    include ForestAdminDatasourceRpc

    describe BindingSymbol do
      let(:route) { described_class.new }
      let(:connection_name) { 'primary' }
      let(:datasource) { instance_double(ForestAdminDatasourceToolkit::Datasource) }

      before do
        allow(ForestAdminRpcAgent::Facades::Container).to receive(:datasource).and_return(datasource)
        allow(datasource).to receive(:build_binding_symbol).and_return('$1')
      end

      describe '#handle_request' do
        it 'forwards the connection name and bind count to the datasource' do
          result = route.handle_request(params: { 'connection_name' => connection_name, 'binds_count' => 2 })

          expect(result).to eq('$1')
          expect(datasource).to have_received(:build_binding_symbol).with(connection_name, [nil, nil])
        end

        it 'defaults the bind count to 0 when not provided' do
          route.handle_request(params: { 'connection_name' => connection_name })

          expect(datasource).to have_received(:build_binding_symbol).with(connection_name, [])
        end

        it 'clamps a negative bind count to 0 instead of raising' do
          route.handle_request(params: { 'connection_name' => connection_name, 'binds_count' => -1 })

          expect(datasource).to have_received(:build_binding_symbol).with(connection_name, [])
        end

        it 'clamps an excessively large bind count instead of allocating it' do
          route.handle_request(params: { 'connection_name' => connection_name, 'binds_count' => 10**12 })

          expect(datasource).to have_received(:build_binding_symbol).with(connection_name,
                                                                          Array.new(described_class::MAX_BINDS_COUNT))
        end

        it 'treats a non-numeric bind count as 0 instead of raising' do
          route.handle_request(params: { 'connection_name' => connection_name,
                                         'binds_count' => { 'not' => 'a number' } })

          expect(datasource).to have_received(:build_binding_symbol).with(connection_name, [])
        end
      end
    end
  end
end
