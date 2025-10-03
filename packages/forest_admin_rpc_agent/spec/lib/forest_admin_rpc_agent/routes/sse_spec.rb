require 'spec_helper'
require 'openssl'
require 'time'
require 'rails'
require 'action_dispatch'

module ForestAdminRpcAgent
  module Routes
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
      end

      describe '#initialize' do
        it 'sets default values' do
          route = described_class.new
          expect(route.instance_variable_get(:@url)).to eq('rpc/sse')
          expect(route.instance_variable_get(:@method)).to eq('get')
          expect(route.instance_variable_get(:@name)).to eq('rpc_sse')
          expect(route.instance_variable_get(:@heartbeat_interval)).to eq(1)
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
        let(:captured_handler) { [] }

        before do
          allow(Kernel).to receive(:trap).and_return(-> {})
          # rubocop:disable RSpec/AnyInstance
          # we need to override sleep here to stop the infinite loop of the SSE stream in the test
          allow_any_instance_of(described_class).to receive(:sleep) { throw :stop }
          # rubocop:enable RSpec/AnyInstance
          allow(rails_router).to receive(:match) do |_, options|
            captured_handler << options[:to]
          end
        end

        it 'streams heartbeat events and closes with RpcServerStop' do
          route.register_rails(rails_router)
          handler = captured_handler.first
          expect(handler).to be_a(Proc)

          allow(route).to receive(:trap).and_yield if route.respond_to?(:trap)
          status, headers, body = handler.call(env)

          expect(status).to eq(200)
          expect(headers['Content-Type']).to eq('text/event-stream')

          chunks = []
          body.each do |chunk|
            chunks << chunk
            break if chunks.join.include?('RpcServerStop')
          end

          text = chunks.join
          expect(text).to include('event: heartbeat')
          expect(text).to include('event: RpcServerStop')
        end

        it 'returns the response from the middleware if status is not 200' do
          route.register_rails(rails_router)
          handler = captured_handler.first
          expect(handler).to be_a(Proc)

          response_unauthorized = ['Unauthorized']
          allow(ForestAdminRpcAgent::Middleware::Authentication).to receive(:new)
            .and_return(lambda { |_env|
                          [401, { 'Content-Type' => 'text/plain' }, response_unauthorized]
                        })

          status, headers, body = handler.call(env)

          expect(status).to eq(401)
          expect(headers['Content-Type']).to eq('text/plain')
          expect(body).to eq(response_unauthorized)
        end

        it 'sets correct headers including X-Accel-Buffering' do
          route.register_rails(rails_router)
          handler = captured_handler.first

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
          handler = captured_handler.first

          catch(:stop) do
            handler.call(env)
          end
        end

        it 'logs stream start message' do
          route.register_rails(rails_router)
          handler = captured_handler.first

          _status, _headers, body = handler.call(env)

          # Consume at least one chunk to trigger start logging
          body.first

          expect(logger).to have_received(:log).with('Debug', '[SSE] Starting stream')
        end

        it 'logs stream stop message on completion' do
          route.register_rails(rails_router)
          handler = captured_handler.first

          _status, _headers, body = handler.call(env)

          # Fully consume the enumerator to trigger the ensure block
          begin
            body.to_a
          rescue StopIteration
            # Expected when enumerator ends
          end

          expect(logger).to have_received(:log).with('Debug', '[SSE] Stream stopped')
        end

        it 'handles IOError during streaming' do
          route.register_rails(rails_router)
          handler = captured_handler.first

          streamer_instance = instance_double(SseStreamer)
          allow(SseStreamer).to receive(:new).and_return(streamer_instance)
          allow(streamer_instance).to receive(:write).and_raise(IOError, 'Connection broken')

          _status, _headers, body = handler.call(env)

          # The error should be caught and logged
          body.first

          expect(logger).to have_received(:log).with('Debug', /Client disconnected/)
        end

        it 'handles errors when sending stop event' do
          route.register_rails(rails_router)
          handler = captured_handler.first

          streamer_instance = instance_double(SseStreamer)
          allow(SseStreamer).to receive(:new).and_return(streamer_instance)
          allow(streamer_instance).to receive(:write) do |_payload, event:|
            raise StandardError, 'Stop failed' if event == 'RpcServerStop'

            throw :stop if event == 'heartbeat'
          end

          _status, _headers, body = handler.call(env)

          body.first

          expect(logger).to have_received(:log).with('Debug', /Error sending stop event/)
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
          expect(routes.first[:path]).to eq('/rpc/sse')
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
    end
  end
end
