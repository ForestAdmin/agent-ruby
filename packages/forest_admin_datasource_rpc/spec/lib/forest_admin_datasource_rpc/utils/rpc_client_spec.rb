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

        context 'when request fails with error responses' do
          let(:url) { '/rpc/test' }

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

            it 'raises BadRequestError with error message' do
              expect { rpc_client.call_rpc(url, method: :get) }.to raise_error(
                ForestAdminAgent::Http::Exceptions::BadRequestError,
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
                ForestAdminAgent::Http::Exceptions::BadRequestError,
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
      end
    end
  end
end
