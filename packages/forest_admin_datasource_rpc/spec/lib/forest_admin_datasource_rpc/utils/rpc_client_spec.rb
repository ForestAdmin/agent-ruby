require 'spec_helper'

module ForestAdminDatasourceRpc
  module Utils
    describe RpcClient do
      subject(:rpc_client) { described_class.new('http://localhost', 'secret') }

      let(:logger) { instance_spy(Logger) }

      before do
        allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
      end

      context 'when the forest admin api is called' do
        let(:response_headers) { {} }
        let(:response) { instance_double(Faraday::Response, status: 200, body: {}, success?: true, headers: response_headers) }
        let(:faraday_connection) { instance_double(Faraday::Connection, send: response) }
        let(:timestamp) { '2025-04-01T14:07:02Z' }

        before do
          allow(Faraday::Connection).to receive(:new).and_return(faraday_connection)
          allow(Time).to receive(:now).and_return(instance_double(Time, utc: instance_double(Time, iso8601: timestamp)))
        end

        it 'returns the body directly on the get method' do
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

        it 'returns the body directly on the get method with payload' do
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

        it 'returns the body directly on the post method' do
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

        it 'returns the body directly on the post method with payload' do
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
      end

      describe '#fetch_schema' do
        let(:response_headers) { {} }
        let(:response) { instance_double(Faraday::Response, status: 200, body: { collections: [] }, success?: true, headers: response_headers) }
        let(:faraday_connection) { instance_double(Faraday::Connection, send: response) }
        let(:timestamp) { '2025-04-01T14:07:02Z' }

        before do
          allow(Faraday::Connection).to receive(:new).and_return(faraday_connection)
          allow(Time).to receive(:now).and_return(instance_double(Time, utc: instance_double(Time, iso8601: timestamp)))
        end

        it 'returns a SchemaResponse with body and etag' do
          result = rpc_client.fetch_schema('/rpc/schema')

          expect(result).to be_a(SchemaResponse)
          expect(result.body).to eq({ collections: [] })
        end

        context 'with If-None-Match header' do
          it 'sends If-None-Match header when if_none_match is provided' do
            rpc_client.fetch_schema('/rpc/schema', if_none_match: 'abc123')

            expect(faraday_connection).to have_received(:send) do |_method, _endpoint, _payload, headers|
              expect(headers['If-None-Match']).to eq('abc123')
            end
          end

          it 'does not send If-None-Match header when if_none_match is nil' do
            rpc_client.fetch_schema('/rpc/schema')

            expect(faraday_connection).to have_received(:send) do |_method, _endpoint, _payload, headers|
              expect(headers).not_to have_key('If-None-Match')
            end
          end
        end

        context 'with ETag in response' do
          let(:response_headers) { { 'ETag' => 'etag123' } }

          it 'extracts ETag from response headers' do
            result = rpc_client.fetch_schema('/rpc/schema')

            expect(result.etag).to eq('etag123')
          end
        end

        context 'with lowercase etag header' do
          let(:response_headers) { { 'etag' => 'lowercase-etag' } }

          it 'extracts etag from lowercase header' do
            result = rpc_client.fetch_schema('/rpc/schema')

            expect(result.etag).to eq('lowercase-etag')
          end
        end

        context 'without ETag in response' do
          let(:response_headers) { {} }

          it 'returns nil for etag' do
            result = rpc_client.fetch_schema('/rpc/schema')

            expect(result.etag).to be_nil
          end
        end

        context 'with 304 Not Modified response' do
          let(:response) { instance_double(Faraday::Response, status: 304, success?: false, headers: response_headers) }

          it 'returns NotModified' do
            result = rpc_client.fetch_schema('/rpc/schema', if_none_match: 'abc123')

            expect(result).to eq(RpcClient::NotModified)
          end
        end
      end

      context 'when request fails with error responses' do
        let(:response_headers) { {} }
        let(:faraday_connection) { instance_double(Faraday::Connection, send: response) }
        let(:timestamp) { '2025-04-01T14:07:02Z' }
        let(:url) { '/rpc/test' }

        before do
          allow(Faraday::Connection).to receive(:new).and_return(faraday_connection)
          allow(Time).to receive(:now).and_return(instance_double(Time, utc: instance_double(Time, iso8601: timestamp)))
        end

        # NOTE: When adding a new error type to ERROR_STATUS_MAP in rpc_client.rb:
        # 1. Add the status code mapping to ERROR_STATUS_MAP
        # 2. Add a test case here following the same pattern
        # 3. The test will automatically verify the mapping works correctly

        context 'with 400 Bad Request' do
          let(:response) do
            instance_double(
              Faraday::Response,
              status: 400,
              success?: false,
              body: { 'error' => 'Invalid parameters' },
              env: Faraday::Env.from(url: url)
            )
          end

          it 'raises ValidationError with error message' do
            expect { rpc_client.call_rpc(url, method: :get) }.to raise_error(
              ForestAdminAgent::Http::Exceptions::ValidationError,
              /Invalid parameters/
            )
          end
        end

        context 'with 401 Unauthorized' do
          let(:response) do
            instance_double(
              Faraday::Response,
              status: 401,
              success?: false,
              body: { 'error' => 'Invalid credentials' },
              env: Faraday::Env.from(url: url)
            )
          end

          it 'raises AuthenticationOpenIdClient error' do
            expect { rpc_client.call_rpc(url, method: :get) }.to raise_error(
              ForestAdminAgent::Http::Exceptions::AuthenticationOpenIdClient,
              /Invalid credentials/
            )
          end
        end

        context 'with 403 Forbidden' do
          let(:response) do
            instance_double(
              Faraday::Response,
              status: 403,
              success?: false,
              body: { 'error' => 'Access denied' },
              env: Faraday::Env.from(url: url)
            )
          end

          it 'raises ForbiddenError' do
            expect { rpc_client.call_rpc(url, method: :get) }.to raise_error(
              ForestAdminAgent::Http::Exceptions::ForbiddenError,
              /Access denied/
            )
          end
        end

        context 'with 404 Not Found' do
          let(:response) do
            instance_double(
              Faraday::Response,
              status: 404,
              success?: false,
              body: { 'error' => 'Resource not found' },
              env: Faraday::Env.from(url: url)
            )
          end

          it 'raises NotFoundError' do
            expect { rpc_client.call_rpc(url, method: :get) }.to raise_error(
              ForestAdminAgent::Http::Exceptions::NotFoundError,
              /Resource not found/
            )
          end
        end

        context 'with 409 Conflict' do
          let(:response) do
            instance_double(
              Faraday::Response,
              status: 409,
              success?: false,
              body: { 'error' => 'Duplicate record' },
              env: Faraday::Env.from(url: url)
            )
          end

          it 'raises ConflictError' do
            expect { rpc_client.call_rpc(url, method: :get) }.to raise_error(
              ForestAdminAgent::Http::Exceptions::ConflictError,
              /Duplicate record/
            )
          end
        end

        context 'with 422 Unprocessable Entity' do
          let(:response) do
            instance_double(
              Faraday::Response,
              status: 422,
              success?: false,
              body: { 'error' => 'Validation failed', 'errors' => ['field is required'] },
              env: Faraday::Env.from(url: url)
            )
          end

          it 'raises UnprocessableError' do
            expect { rpc_client.call_rpc(url, method: :get) }.to raise_error(
              ForestAdminAgent::Http::Exceptions::UnprocessableError,
              /Validation failed/
            )
          end
        end

        context 'with 500 Internal Server Error' do
          let(:response) do
            instance_double(
              Faraday::Response,
              status: 500,
              success?: false,
              body: { 'error' => 'Something went wrong' },
              env: Faraday::Env.from(url: url)
            )
          end

          it 'raises ForestException with server error message' do
            expect { rpc_client.call_rpc(url, method: :get) }.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ForestException,
              /Server Error.*Something went wrong/
            )
          end
        end

        context 'with error body as string instead of JSON' do
          let(:response) do
            instance_double(
              Faraday::Response,
              status: 500,
              success?: false,
              body: 'Internal Server Error',
              env: Faraday::Env.from(url: url)
            )
          end

          it 'parses string error as message' do
            expect { rpc_client.call_rpc(url, method: :get) }.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ForestException,
              /Internal Server Error/
            )
          end
        end

        context 'with error body using "message" key instead of "error"' do
          let(:response) do
            instance_double(
              Faraday::Response,
              status: 400,
              success?: false,
              body: { 'message' => 'Custom error message' },
              env: Faraday::Env.from(url: url)
            )
          end

          it 'extracts message correctly' do
            expect { rpc_client.call_rpc(url, method: :get) }.to raise_error(
              ForestAdminAgent::Http::Exceptions::ValidationError,
              /Custom error message/
            )
          end
        end

        context 'with empty error body' do
          let(:response) do
            instance_double(
              Faraday::Response,
              status: 500,
              success?: false,
              body: '',
              env: Faraday::Env.from(url: url)
            )
          end

          it 'raises error with default message' do
            expect { rpc_client.call_rpc(url, method: :get) }.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ForestException,
              /Server Error.*Unknown error/
            )
          end
        end
      end

      context 'when connection fails' do
        let(:faraday_connection) { instance_double(Faraday::Connection) }
        let(:timestamp) { '2025-04-01T14:07:02Z' }

        before do
          allow(Faraday).to receive(:new).and_return(faraday_connection)
          allow(Time).to receive(:now).and_return(instance_double(Time, utc: instance_double(Time, iso8601: timestamp)))
        end

        context 'with Faraday::ConnectionFailed' do
          before do
            allow(faraday_connection).to receive(:send).and_raise(
              Faraday::ConnectionFailed.new('Failed to open TCP connection to localhost:3039')
            )
          end

          it 'logs the connection error' do
            expect { rpc_client.call_rpc('/rpc/test', method: :get) }.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ForestException
            )

            expect(logger).to have_received(:log).with(
              'Error',
              %r{\[RPC Client\] Connection failed to http://localhost/rpc/test: Failed to open TCP connection}
            )
          end

          it 'raises ForestException with user-friendly message' do
            expect { rpc_client.call_rpc('/rpc/test', method: :get) }.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ForestException,
              %r{RPC connection failed: Unable to connect to http://localhost.*Please check if the RPC server is running}
            )
          end

          it 'handles connection failure in fetch_schema' do
            expect { rpc_client.fetch_schema('/rpc/schema') }.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ForestException,
              /RPC connection failed/
            )
          end
        end

        context 'with Faraday::TimeoutError' do
          before do
            allow(faraday_connection).to receive(:send).and_raise(
              Faraday::TimeoutError.new('Net::ReadTimeout')
            )
          end

          it 'logs the timeout error' do
            expect { rpc_client.call_rpc('/rpc/test', method: :get) }.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ForestException
            )

            expect(logger).to have_received(:log).with(
              'Error',
              %r{\[RPC Client\] Request timeout to http://localhost/rpc/test}
            )
          end

          it 'raises ForestException with user-friendly message' do
            expect { rpc_client.call_rpc('/rpc/test', method: :get) }.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ForestException,
              %r{RPC request timeout: The RPC server at http://localhost did not respond in time}
            )
          end

          it 'handles timeout in fetch_schema' do
            expect { rpc_client.fetch_schema('/rpc/schema') }.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ForestException,
              /RPC request timeout/
            )
          end
        end
      end
    end
  end
end
