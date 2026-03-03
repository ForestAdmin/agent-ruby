require 'spec_helper'
require 'rack'

module ForestAdminRpcAgent
  module Routes
    include ForestAdminDatasourceRpc
    describe Schema do
      let(:route) { described_class.new }
      let(:agent) { instance_double(ForestAdminRpcAgent::Agent) }
      let(:logger) { instance_double(Logger) }

      let(:cached_schema) do
        {
          some_key: 'some_value',
          collections: [
            { fields: ['id', 'total'], name: 'orders' },
            { fields: ['id', 'email'], name: 'users' }
          ],
          native_query_connections: [
            { name: 'primary' }
          ],
          etag: 'abc123hash'
        }
      end

      before do
        allow(ForestAdminRpcAgent::Agent).to receive(:instance).and_return(agent)
        allow(ForestAdminRpcAgent::Facades::Container).to receive(:logger).and_return(logger)
        allow(logger).to receive(:log)
        allow(agent).to receive(:cached_schema).and_return(cached_schema)
      end

      describe '#handle_request' do
        it 'returns the schema' do
          result = route.handle_request({})

          expect(result[:status]).to eq(200)
          expect(result[:content]).to eq(cached_schema)
        end

        context 'when client provides matching If-None-Match header' do
          let(:mock_request) do
            instance_double(::Rack::Request, get_header: 'abc123hash')
          end

          it 'returns 304 Not Modified' do
            result = route.handle_request({ request: mock_request })

            expect(result[:status]).to eq(304)
            expect(result[:content]).to be_nil
          end

          it 'logs debug message' do
            route.handle_request({ request: mock_request })

            expect(logger).to have_received(:log).with('Debug', 'ETag matches, returning 304 Not Modified')
          end
        end

        context 'when client provides non-matching If-None-Match header' do
          let(:mock_request) do
            instance_double(::Rack::Request, get_header: 'different_hash')
          end

          it 'returns the full schema' do
            result = route.handle_request({ request: mock_request })

            expect(result[:status]).to eq(200)
            expect(result[:content]).to eq(cached_schema)
          end
        end

        context 'when client does not provide If-None-Match header' do
          let(:mock_request) do
            instance_double(::Rack::Request, get_header: nil)
          end

          it 'returns the full schema' do
            result = route.handle_request({ request: mock_request })

            expect(result[:status]).to eq(200)
            expect(result[:content]).to eq(cached_schema)
          end
        end

        context 'with Sinatra-style request (env)' do
          let(:mock_request) do
            Struct.new(:env).new({ 'HTTP_IF_NONE_MATCH' => 'abc123hash' })
          end

          it 'extracts If-None-Match from env and returns 304 when hash matches' do
            result = route.handle_request({ request: mock_request })

            expect(result[:status]).to eq(304)
            expect(result[:content]).to be_nil
          end
        end

        context 'without request object' do
          it 'returns the full schema' do
            result = route.handle_request({})

            expect(result[:status]).to eq(200)
            expect(result[:content]).to eq(cached_schema)
          end
        end
      end
    end
  end
end
