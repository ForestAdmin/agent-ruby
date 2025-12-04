require 'spec_helper'
require 'openssl'
require 'time'
require 'rails'
require 'action_dispatch'

module ForestAdminRpcAgent
  module Routes
    # Custom exception for tests to stop the loop
    class TestStopLoop < StandardError; end

    describe Sse do
      let(:route) { described_class.new }
      let(:timestamp) { Time.now.utc.iso8601 }
      let(:auth_secret) { 'test-secret' }
      let(:signature) { OpenSSL::HMAC.hexdigest('SHA256', auth_secret, timestamp) }
      let(:logger) { instance_double(Logger, log: nil) }
      let(:env) do
        {
          'REQUEST_METHOD' => 'GET',
          'PATH_INFO' => '/forest/rpc/sse',
          'HTTP_X_TIMESTAMP' => timestamp,
          'HTTP_X_SIGNATURE' => signature
        }
      end

      before do
        ForestAdminRpcAgent.config.auth_secret = auth_secret
        allow(ForestAdminRpcAgent::Facades::Container).to receive(:logger).and_return(logger)
        # Clear used signatures to avoid replay attack protection between tests
        ForestAdminRpcAgent::Middleware::Authentication.class_variable_set(:@@used_signatures, {})
        # Reset connection manager between tests
        ForestAdminRpcAgent::SseConnectionManager.reset!
      end

      after do
        ForestAdminRpcAgent::SseConnectionManager.reset!
      end

      describe '#initialize' do
        it 'sets default values' do
          route = described_class.new
          expect(route.instance_variable_get(:@url)).to eq('sse')
          expect(route.instance_variable_get(:@method)).to eq('get')
          expect(route.instance_variable_get(:@name)).to eq('rpc_sse')
          expect(route.instance_variable_get(:@heartbeat_interval)).to eq(10)
        end

        it 'accepts custom heartbeat_interval' do
          route = described_class.new('custom/sse', 'post', 'custom_sse', heartbeat_interval: 5)
          expect(route.instance_variable_get(:@url)).to eq('custom/sse')
          expect(route.instance_variable_get(:@method)).to eq('post')
          expect(route.instance_variable_get(:@name)).to eq('custom_sse')
          expect(route.instance_variable_get(:@heartbeat_interval)).to eq(5)
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
        let(:trapped_handlers) { {} }

        # Use instance variable to ensure it's shared but can be reset
        before do
          @captured_handlers = []

          # Capture trap handlers so we can trigger them in tests
          allow(Kernel).to receive(:trap) do |signal, handler|
            trapped_handlers[signal] = handler if handler.is_a?(Proc)
            -> {} # Return a dummy handler
          end

          allow(rails_router).to receive(:match) do |_, options|
            @captured_handlers << options[:to]
          end
        end

        # rubocop:disable RSpec/ExampleLength
        it 'streams heartbeat events' do
          route.register_rails(rails_router)
          handler = @captured_handlers.first
          expect(handler).to be_a(Proc)

          # Limit to just 1 heartbeat to test the stream works
          sleep_count = 0
          allow(Kernel).to receive(:sleep) do |_duration|
            sleep_count += 1
            raise TestStopLoop if sleep_count >= 1
          end

          status, headers, body = handler.call(env)

          expect(status).to eq(200)
          expect(headers['Content-Type']).to eq('text/event-stream')

          chunks = []
          begin
            body.each do |chunk|
              chunks << chunk
              break if chunks.size >= 1 # Get at least 1 heartbeat
            end
          rescue TestStopLoop
            # Expected
          end

          text = chunks.join
          expect(text).to include('event: heartbeat')
        end
        # rubocop:enable RSpec/ExampleLength

        it 'sets correct headers including X-Accel-Buffering' do
          route.register_rails(rails_router)
          handler = @captured_handlers.first
          status, headers, _body = handler.call(env)

          expect(status).to eq(200)
          expect(headers['Content-Type']).to eq('text/event-stream')
          expect(headers['Cache-Control']).to eq('no-cache')
          expect(headers['Connection']).to eq('keep-alive')
          expect(headers['X-Accel-Buffering']).to eq('no')
        end

        it 'uses custom heartbeat interval' do
          custom_route = described_class.new('rpc/sse', 'get', 'rpc_sse', heartbeat_interval: 3)
          allow(custom_route).to receive(:sleep) do |interval|
            expect(interval).to eq(3)
            throw :stop
          end

          custom_route.register_rails(rails_router)
          handler = @captured_handlers.first

          catch(:stop) do
            handler.call(env)
          end
        end

        it 'logs stream start message' do
          route.register_rails(rails_router)
          handler = @captured_handlers.first

          # Mock sleep to stop after first iteration
          allow(Kernel).to receive(:sleep) do |_duration|
            raise TestStopLoop
          end

          _status, _headers, body = handler.call(env)

          begin
            body.first
          rescue TestStopLoop
            # Expected
          end

          expect(logger).to have_received(:log).with('Debug', '[SSE] Starting stream')
        end

        it 'logs stream stop message on completion' do
          route.register_rails(rails_router)
          handler = @captured_handlers.first

          sleep_count = 0
          allow(Kernel).to receive(:sleep) do |_duration|
            sleep_count += 1
            raise TestStopLoop if sleep_count >= 1
          end

          _status, _headers, body = handler.call(env)

          chunks = []
          begin
            body.each do |chunk|
              chunks << chunk
              break if chunks.size >= 2 # Get at least 2 chunks before stopping
            end
          rescue TestStopLoop
            # Expected - this triggers the ensure block
          end

          expect(logger).to have_received(:log).with('Debug', '[SSE] Stream stopped')
        end

        it 'handles IOError during streaming' do
          route.register_rails(rails_router)
          handler = @captured_handlers.first

          streamer_instance = instance_double(SseStreamer)
          allow(SseStreamer).to receive(:new).and_return(streamer_instance)
          allow(streamer_instance).to receive(:write).and_raise(IOError, 'Connection broken')

          _status, _headers, body = handler.call(env)

          # The error should be caught and logged
          begin
            body.first
          rescue IOError, TestStopLoop
            # Expected - IOError is caught inside enumerator
          end

          expect(logger).to have_received(:log).with('Debug', /Client disconnected/)
        end

        # This test is placed last to avoid mock persistence affecting other tests
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
          handler = @captured_handlers.first
          expect(handler).to be_a(Proc)

          status, headers, body = handler.call(env)

          expect(status).to eq(401)
          expect(headers['Content-Type']).to eq('text/plain')
          expect(body).to eq(response_unauthorized)
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
          allow(Kernel).to receive(:trap).and_return(-> {})
        end

        it 'registers a Sinatra route with correct method and path' do
          route.register_sinatra(sinatra_app)

          routes = sinatra_app.registered_routes
          expect(routes.length).to eq(1)
          expect(routes.first[:method]).to eq(:get)
          expect(routes.first[:path]).to eq('/sse')
          expect(routes.first[:block]).to be_a(Proc)
        end

        it 'registers route with custom URL' do
          custom_route = described_class.new('custom/path', 'post', 'custom_sse')
          custom_route.register_sinatra(sinatra_app)

          routes = sinatra_app.registered_routes
          expect(routes.first[:method]).to eq(:post)
          expect(routes.first[:path]).to eq('/custom/path')
        end
      end

      describe 'connection manager integration' do
        let(:rails_router) { instance_double(ActionDispatch::Routing::Mapper) }

        before do
          @captured_handlers = []

          allow(Kernel).to receive(:trap) do |_signal, _handler|
            -> {} # Return a dummy handler
          end

          allow(rails_router).to receive(:match) do |_, options|
            @captured_handlers << options[:to]
          end
        end

        it 'registers connection with connection manager' do
          route.register_rails(rails_router)
          handler = @captured_handlers.first

          allow(Kernel).to receive(:sleep) do |_duration|
            raise TestStopLoop
          end

          # Connection is registered when handler.call is invoked
          _status, _headers, body = handler.call(env)

          # Connection should be registered after handler.call but before enumeration
          registered_connection = ForestAdminRpcAgent::SseConnectionManager.current_connection
          expect(registered_connection).not_to be_nil
          expect(registered_connection).to be_a(ForestAdminRpcAgent::SseConnectionManager::Connection)

          begin
            body.first
          rescue TestStopLoop
            # Expected
          end
        end

        it 'terminates previous connection when new request arrives' do
          route.register_rails(rails_router)
          handler = @captured_handlers.first

          allow(Kernel).to receive(:sleep) do |_duration|
            raise TestStopLoop
          end

          # First request - don't iterate the body so connection stays registered
          _status, _headers, _first_body = handler.call(env)
          first_connection = ForestAdminRpcAgent::SseConnectionManager.current_connection
          expect(first_connection.active?).to be true

          # Clear signatures for second request
          ForestAdminRpcAgent::Middleware::Authentication.class_variable_set(:@@used_signatures, {})

          # Second request - should terminate first connection immediately upon registration
          _status, _headers, _second_body = handler.call(env)
          second_connection = ForestAdminRpcAgent::SseConnectionManager.current_connection

          # First connection should now be terminated by second request's registration
          expect(first_connection.active?).to be false
          expect(second_connection.active?).to be true
          expect(second_connection).not_to eq(first_connection)
        end

        it 'uses connection.active? as loop condition' do
          # This test verifies the loop stops when connection is terminated
          # by testing the connection manager behavior directly
          connection = ForestAdminRpcAgent::SseConnectionManager.register_connection

          iterations = 0
          while connection.active? && iterations < 5
            iterations += 1
            # Simulate new connection arriving after 2 iterations
            ForestAdminRpcAgent::SseConnectionManager.register_connection if iterations == 2
          end

          # Loop should have stopped after 2 iterations when connection was terminated
          expect(iterations).to eq(2)
          expect(connection.active?).to be false
        end
      end
    end
  end
end
