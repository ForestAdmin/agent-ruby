require 'spec_helper'

module ForestAdminRpcAgent
  module Routes
    describe HealthRoute do
      let(:route) { described_class.new }

      describe '#initialize' do
        it 'sets the correct url' do
          expect(route.instance_variable_get(:@url)).to eq('/')
        end

        it 'sets the correct method' do
          expect(route.instance_variable_get(:@method)).to eq('get')
        end

        it 'sets the correct name' do
          expect(route.instance_variable_get(:@name)).to eq('rpc_forest')
        end
      end

      describe '#handle_request' do
        it 'returns a hash with error null and running message' do
          result = route.handle_request({})

          expect(result).to be_a(Hash)
          expect(result[:error]).to be_nil
          expect(result[:message]).to eq('Agent is running')
        end
      end
    end
  end
end
