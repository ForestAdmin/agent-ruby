require 'spec_helper'

module ForestAdminRpcAgent
  module Routes
    include ForestAdminDatasourceRpc
    describe Schema do
      let(:route) { described_class.new }
      let(:agent) { instance_double(ForestAdminRpcAgent::Agent) }
      let(:logger) { instance_double(Logger) }
      let(:cached_hash) { 'abc123hash' }

      let(:cached_schema) do
        {
          some_key: 'some_value',
          collections: [
            { fields: ['id', 'total'], name: 'orders' },
            { fields: ['id', 'email'], name: 'users' }
          ],
          native_query_connections: [
            { name: 'primary' }
          ]
        }
      end

      before do
        allow(ForestAdminRpcAgent::Agent).to receive(:instance).and_return(agent)
        allow(ForestAdminRpcAgent::Facades::Container).to receive(:logger).and_return(logger)
        allow(logger).to receive(:log)
        allow(agent).to receive_messages(rpc_schema: cached_schema,
                                         cached_schema_hash: cached_hash,
                                         schema_hash_matches?: false)
      end

      describe '#handle_request' do
        it 'returns the schema with ETag header' do
          result = route.handle_request({})

          expect(result[:status]).to eq(200)
          expect(result[:content]).to eq(cached_schema)
          expect(result[:headers]['ETag']).to eq(%("#{cached_hash}"))
        end

        context 'when client provides matching If-None-Match header' do
          let(:mock_request) do
            instance_double(Rack::Request, get_header: %("#{cached_hash}"))
          end

          before do
            allow(agent).to receive(:schema_hash_matches?) { |hash| hash == cached_hash }
          end

          it 'returns 304 Not Modified with ETag header' do
            result = route.handle_request({ request: mock_request })

            expect(result[:status]).to eq(304)
            expect(result[:content]).to be_nil
            expect(result[:headers]['ETag']).to eq(%("#{cached_hash}"))
          end

          it 'logs debug message' do
            route.handle_request({ request: mock_request })

            expect(logger).to have_received(:log).with('Debug', 'ETag matches, returning 304 Not Modified')
          end
        end

        context 'when client provides non-matching If-None-Match header' do
          let(:mock_request) do
            instance_double(Rack::Request, get_header: '"different_hash"')
          end

          it 'returns the full schema with ETag header' do
            result = route.handle_request({ request: mock_request })

            expect(result[:status]).to eq(200)
            expect(result[:content]).to eq(cached_schema)
            expect(result[:headers]['ETag']).to eq(%("#{cached_hash}"))
          end
        end

        context 'when client does not provide If-None-Match header' do
          let(:mock_request) do
            instance_double(Rack::Request, get_header: nil)
          end

          it 'returns the full schema' do
            result = route.handle_request({ request: mock_request })

            expect(result[:status]).to eq(200)
            expect(result[:content]).to eq(cached_schema)
          end
        end

        context 'with Sinatra-style request (env)' do
          let(:mock_request) do
            request = instance_double(Sinatra::Request)
            allow(request).to receive(:respond_to?).with(:get_header).and_return(false)
            allow(request).to receive(:respond_to?).with(:env).and_return(true)
            allow(request).to receive(:env).and_return({ 'HTTP_IF_NONE_MATCH' => %("#{cached_hash}") })
            request
          end

          it 'extracts If-None-Match from env and returns 304 when hash matches' do
            allow(agent).to receive(:schema_hash_matches?) { |hash| hash == cached_hash }

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
