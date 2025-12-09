require 'spec_helper'
require 'openssl'
require 'time'
require 'rails'
require 'action_dispatch'

module ForestAdminRpcAgent
  module Routes
    describe Health do
      let(:route) { described_class.new }
      let(:timestamp) { Time.now.utc.iso8601 }
      let(:auth_secret) { 'test-secret' }
      let(:signature) { OpenSSL::HMAC.hexdigest('SHA256', auth_secret, timestamp) }
      let(:logger) { instance_double(Logger, log: nil) }
      let(:env) do
        {
          'REQUEST_METHOD' => 'GET',
          'PATH_INFO' => '/forest/rpc/health',
          'HTTP_X_TIMESTAMP' => timestamp,
          'HTTP_X_SIGNATURE' => signature
        }
      end

      before do
        ForestAdminRpcAgent.config.auth_secret = auth_secret
        allow(ForestAdminRpcAgent::Facades::Container).to receive(:logger).and_return(logger)
        # Clear used signatures to avoid replay attack protection between tests
        ForestAdminRpcAgent::Middleware::Authentication.class_variable_set(:@@used_signatures, {})
      end

      describe '#initialize' do
        it 'sets default values' do
          route = described_class.new
          expect(route.instance_variable_get(:@url)).to eq('health')
          expect(route.instance_variable_get(:@method)).to eq('get')
          expect(route.instance_variable_get(:@name)).to eq('rpc_health')
        end

        it 'accepts custom parameters' do
          route = described_class.new('custom/health', 'post', 'custom_health')
          expect(route.instance_variable_get(:@url)).to eq('custom/health')
          expect(route.instance_variable_get(:@method)).to eq('post')
          expect(route.instance_variable_get(:@name)).to eq('custom_health')
        end
      end

      describe '#registered' do
        it 'raises NotImplementedError for unsupported app types' do
          unsupported_app = Object.new

          expect do
            route.registered(unsupported_app)
          end.to raise_error(NotImplementedError, /Unsupported application type/)
        end
      end

      context 'when the app is an ActionDispatch::Routing::Mapper' do
        let(:rails_router) { instance_double(ActionDispatch::Routing::Mapper) }
        let(:captured_handlers) { [] }

        before do
          allow(rails_router).to receive(:match) do |_, options|
            captured_handlers << options[:to]
          end
        end

        it 'returns status 200 with JSON response' do
          route.register_rails(rails_router)
          handler = captured_handlers.first
          expect(handler).to be_a(Proc)

          status, headers, body = handler.call(env)

          expect(status).to eq(200)
          expect(headers['Content-Type']).to eq('application/json')
          expect(body).to be_an(Array)

          response = JSON.parse(body.first)
          expect(response['status']).to eq('ok')
          expect(response['version']).to eq(ForestAdminRpcAgent::VERSION)
        end

        it 'sets correct Content-Type header' do
          route.register_rails(rails_router)
          handler = captured_handlers.first

          status, headers, _body = handler.call(env)

          expect(status).to eq(200)
          expect(headers['Content-Type']).to eq('application/json')
        end

        it 'logs health check request' do
          route.register_rails(rails_router)
          handler = captured_handlers.first

          handler.call(env)

          expect(logger).to have_received(:log).with('Debug', '[Health] Health check request received')
        end

        it 'returns the response from the middleware if status is not 200' do
          # Create a mock authentication middleware that returns 401
          response_unauthorized = ['Unauthorized']
          mock_auth_middleware = instance_double(
            ForestAdminRpcAgent::Middleware::Authentication,
            call: [401, { 'Content-Type' => 'text/plain' }, response_unauthorized]
          )

          # Mock Authentication.new to return our mock middleware
          allow(ForestAdminRpcAgent::Middleware::Authentication).to receive(:new)
            .and_return(mock_auth_middleware)

          route.register_rails(rails_router)
          handler = captured_handlers.first
          expect(handler).to be_a(Proc)

          status, headers, body = handler.call(env)

          expect(status).to eq(401)
          expect(headers['Content-Type']).to eq('text/plain')
          expect(body).to eq(response_unauthorized)
        end

        it 'includes version in response' do
          route.register_rails(rails_router)
          handler = captured_handlers.first

          _status, _headers, body = handler.call(env)

          response = JSON.parse(body.first)
          expect(response).to have_key('version')
          expect(response['version']).to be_a(String)
        end
      end

      context 'when the app is Sinatra::Base' do
        let(:sinatra_app) do
          Class.new do
            def self.ancestors
              [Sinatra::Base]
            end

            def self.send(method, path, &block)
              @registered_routes ||= []
              @registered_routes << { method: method, path: path, block: block }
            end

            def self.registered_routes
              @registered_routes
            end
          end
        end

        before do
          stub_const('Sinatra::Base', Class.new)
        end

        it 'registers a Sinatra route with correct method and path' do
          route.register_sinatra(sinatra_app)

          routes = sinatra_app.registered_routes
          expect(routes.length).to eq(1)
          expect(routes.first[:method]).to eq(:get)
          expect(routes.first[:path]).to eq('/health')
          expect(routes.first[:block]).to be_a(Proc)
        end

        it 'registers route with custom URL' do
          custom_route = described_class.new('custom/path', 'post', 'custom_health')
          custom_route.register_sinatra(sinatra_app)

          routes = sinatra_app.registered_routes
          expect(routes.first[:method]).to eq(:post)
          expect(routes.first[:path]).to eq('/custom/path')
        end
      end
    end
  end
end
