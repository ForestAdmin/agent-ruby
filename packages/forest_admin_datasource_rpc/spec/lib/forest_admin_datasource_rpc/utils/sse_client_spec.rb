require 'spec_helper'

module ForestAdminDatasourceRpc
  module Utils
    describe SseClient do
      let(:uri) { 'https://example.com/sse' }
      let(:secret) { 'my-secret' }
      let(:logger) { instance_spy(Logger) }
      let(:callback) { instance_double(Proc, call: nil) }

      before do
        allow(ForestAdminRpcAgent::Facades::Container).to receive(:logger).and_return(logger)
      end

      describe '#start' do
        it 'connects to SSE with the expected headers' do
          fake_client = instance_double(SSE::Client)
          allow(SSE::Client).to receive(:new).and_yield(fake_client)
          allow(fake_client).to receive(:on_event)
          allow(fake_client).to receive(:on_error)

          timestamp = '2025-01-01T12:00:00Z'
          signature = OpenSSL::HMAC.hexdigest('SHA256', secret, timestamp)
          # fix the timestamp to a specific value
          allow(Time).to receive(:now).and_return(Time.parse(timestamp))

          client = described_class.new(uri, secret) { callback.call }
          client.start

          expect(SSE::Client).to have_received(:new).with(
            uri,
            headers: {
              'Accept' => 'text/event-stream',
              'X_TIMESTAMP' => timestamp,
              'X_SIGNATURE' => signature
            }
          )
        end

        it 'does not start if already closed' do
          allow(SSE::Client).to receive(:new)

          client = described_class.new(uri, secret) { callback.call }
          # we need to close the client before starting it
          client.close
          # Then we try to start
          client.start

          # finally, we check that it didn't try to connect
          expect(SSE::Client).not_to have_received(:new)
        end
      end

      describe '#close' do
        it 'closes the SSE client' do
          fake_client = instance_double(SSE::Client, close: true)
          allow(SSE::Client).to receive(:new).and_return(fake_client)
          allow(fake_client).to receive(:on_event)
          allow(fake_client).to receive(:on_error)

          client = described_class.new(uri, secret) { callback.call }
          client.start
          client.close

          expect(fake_client).to have_received(:close)
        end

        it 'does not close again if already closed' do
          client = described_class.new(uri, secret) { callback.call }
          client.close

          expect { client.close }.not_to raise_error
        end
      end

      describe '#handle_event' do
        it 'calls the on_rpc_stop callback when RpcServerStop is received' do
          client = described_class.new(uri, secret) { callback.call }

          event = Struct.new(:type, :data).new('RpcServerStop', '')
          client.send(:handle_event, event)

          expect(callback).to have_received(:call)
        end

        it 'ignores heartbeat events' do
          client = described_class.new(uri, secret) { callback.call }

          event = Struct.new(:type, :data).new('heartbeat', '')
          client.send(:handle_event, event)

          expect(callback).not_to have_received(:call)
          expect(logger).not_to have_received(:log).with('Debug', /heartbeat/i)
        end

        it 'logs unknown events' do
          client = described_class.new(uri, secret) { callback.call }

          event = Struct.new(:type, :data).new('FooEvent', 'hello')
          client.send(:handle_event, event)

          expect(logger).to have_received(:log).with('Debug', '[SSE] Unknown event: FooEvent with payload: hello')
        end
      end
    end
  end
end
