require 'spec_helper'
require 'shared/schema'
require 'logger'

module ForestAdminDatasourceRpc
  describe ForestAdminDatasourceRpc do
    it 'has a version number' do
      expect(described_class::VERSION).not_to be_nil
    end

    describe 'build' do
      before do
        logger = instance_double(Logger, log: nil)
        allow(ForestAdminAgent::Facades::Container).to receive_messages(logger: logger, cache: 'secret')
        allow(Utils::RpcClient).to receive(:new).and_return(rpc_client)
      end

      include_examples 'with introspection'

      context 'when server is running' do
        let(:rpc_client) { instance_double(Utils::RpcClient, call_rpc: introspection) }

        it 'build datasource' do
          datasource = described_class.build({ uri: 'http://localhost' })

          expect(datasource).to be_a(ForestAdminDatasourceRpc::Datasource)
        end
      end

      context 'when server is not running' do
        let(:rpc_client) { instance_double(Utils::RpcClient, call_rpc: nil) }

        it 'returns empty datasource and logs error' do
          allow(rpc_client).to receive(:call_rpc).and_raise('server not running')

          datasource = described_class.build({ uri: 'http://localhost' })

          expect(datasource).to be_a(ForestAdminDatasourceToolkit::Datasource)
          expect(ForestAdminAgent::Facades::Container.logger).to have_received(:log).with(
            'Error',
            a_string_matching(%r{Failed to get schema from RPC agent at http://localhost.*server not running})
          )
        end
      end
    end
  end
end
