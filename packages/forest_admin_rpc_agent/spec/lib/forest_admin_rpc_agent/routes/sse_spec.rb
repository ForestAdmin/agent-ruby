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
      end
    end
  end
end
