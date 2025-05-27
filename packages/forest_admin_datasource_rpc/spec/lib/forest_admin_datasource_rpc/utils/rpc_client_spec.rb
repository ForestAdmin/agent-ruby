require 'spec_helper'

module ForestAdminDatasourceRpc
  module Utils
    describe RpcClient do
      subject(:rpc_client) { described_class.new('http://localhost', 'secret') }

      context 'when the forest admin api is called' do
        let(:response) { instance_double(Faraday::Response, status: 200, body: {}, success?: true) }
        let(:faraday_connection) { instance_double(Faraday::Connection, send: response) }
        let(:timestamp) { '2025-04-01T14:07:02Z' }

        before do
          allow(Faraday::Connection).to receive(:new).and_return(faraday_connection)
          allow(Time).to receive(:now).and_return(instance_double(Time, utc: instance_double(Time, iso8601: timestamp)))
        end

        it 'returns a response on the get method' do
          result = rpc_client.call_rpc('/rpc/test', method: :get)

          expect(faraday_connection).to have_received(:send) do |method, endpoint, payload, headers|
            expect(method).to eq(:get)
            expect(endpoint).to eq('/rpc/test')
            expect(payload).to be_nil
            expect(headers).to eq(
              {
                'Content-Type' => 'application/json',
                'X_TIMESTAMP' => timestamp,
                'X_SIGNATURE' => OpenSSL::HMAC.hexdigest('SHA256', 'secret', timestamp)
              }
            )
          end

          expect(result).to eq({})
        end

        it 'returns a response on the get method with payload' do
          result = rpc_client.call_rpc('/rpc/test', method: :get, payload: { foo: 'arg' })

          expect(faraday_connection).to have_received(:send) do |method, endpoint, payload, headers|
            expect(method).to eq(:get)
            expect(endpoint).to eq('/rpc/test')
            expect(payload).to eq({ foo: 'arg' })
            expect(headers).to eq(
              {
                'Content-Type' => 'application/json',
                'X_TIMESTAMP' => timestamp,
                'X_SIGNATURE' => OpenSSL::HMAC.hexdigest('SHA256', 'secret', timestamp)
              }
            )
          end

          expect(result).to eq({})
        end

        it 'returns a response on the post method' do
          result = rpc_client.call_rpc('/rpc/test', method: :post)

          expect(faraday_connection).to have_received(:send) do |method, endpoint, payload, headers|
            expect(method).to eq(:post)
            expect(endpoint).to eq('/rpc/test')
            expect(payload).to be_nil
            expect(headers).to eq(
              {
                'Content-Type' => 'application/json',
                'X_TIMESTAMP' => timestamp,
                'X_SIGNATURE' => OpenSSL::HMAC.hexdigest('SHA256', 'secret', timestamp)
              }
            )
          end

          expect(result).to eq({})
        end

        it 'returns a response on the post method with payload' do
          result = rpc_client.call_rpc('/rpc/test', method: :post, payload: { foo: 'arg' })

          expect(faraday_connection).to have_received(:send) do |method, endpoint, payload, headers|
            expect(method).to eq(:post)
            expect(endpoint).to eq('/rpc/test')
            expect(payload).to eq({ foo: 'arg' })
            expect(headers).to eq(
              {
                'Content-Type' => 'application/json',
                'X_TIMESTAMP' => timestamp,
                'X_SIGNATURE' => OpenSSL::HMAC.hexdigest('SHA256', 'secret', timestamp)
              }
            )
          end

          expect(result).to eq({})
        end

        context 'when request failed' do
          let(:response) do
            instance_double(
              Faraday::Response,
              status: 500,
              success?: false,
              env: Faraday::Env.from(url: '/rpc/test')
            )
          end

          it 'raise an error' do
            expect { rpc_client.call_rpc('/rpc/test', method: :get) }.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ForestException,
              '🌳🌳🌳 RPC request failed: 500 for uri /rpc/test'
            )
          end
        end
      end
    end
  end
end
