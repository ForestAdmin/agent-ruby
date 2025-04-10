require 'spec_helper'
require 'shared/schema'
require 'logger'

module ForestAdminDatasourceRpc
  include ForestAdminDatasourceToolkit::Components::Query
  include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

  describe Datasource do
    before do
      logger = instance_double(Logger, log: nil)
      allow(ForestAdminRpcAgent::Facades::Container).to receive_messages(logger: logger, cache: 'secret')
      allow(Utils::RpcClient).to receive(:new).and_return(rpc_client)
    end

    let(:rpc_client) { instance_double(Utils::RpcClient, call_rpc: {}) }
    let(:datasource) { described_class.new({ uri: 'http://localhost' }, introspection) }
    let(:caller) { build_caller }

    include_examples 'with introspection'

    context 'when initialize the datasource' do
      it 'add collections' do
        expect(datasource.collections.keys).to include('Product', 'Manufacturer')
      end

      it 'add charts' do
        expect(datasource.schema[:charts]).to include('appointments')
      end
    end

    context 'when call render_chart' do
      it 'forward the call to the server' do
        datasource.render_chart(caller, 'my_chart')

        expect(rpc_client).to have_received(:call_rpc) do |url, options|
          expect(url).to eq('forest/rpc/datasource-chart')
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq({ caller: caller.to_h, chart: 'my_chart' })
        end
      end
    end
  end
end
