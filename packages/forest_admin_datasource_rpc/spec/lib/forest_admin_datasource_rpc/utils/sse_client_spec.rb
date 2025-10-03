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

      describe '#initialize' do
        it 'initializes with correct attributes' do
          client = described_class.new(uri, secret) { callback.call }

          expect(client.instance_variable_get(:@uri)).to eq(uri)
          expect(client.instance_variable_get(:@auth_secret)).to eq(secret)
          expect(client.instance_variable_get(:@closed)).to be false
          expect(client.instance_variable_get(:@connection_attempts)).to eq(0)
        end

        it 'exposes closed status via attr_reader' do
          client = described_class.new(uri, secret) { callback.call }

          expect(client.closed).to be false

          client.close

          expect(client.closed).to be true
        end
      end

      describe '#start' do
        it 'connects to SSE with the expected headers' do
          fake_client = instance_double(SSE::Client)
          allow(SSE::Client).to receive(:new).and_yield(fake_client)
          allow(fake_client).to receive(:on_event)
          allow(fake_client).to receive(:on_error)

          timestamp = '2025-01-01T12:00:00.000Z'
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

        it 'increments connection attempts counter' do
          fake_client = instance_double(SSE::Client)
          allow(SSE::Client).to receive(:new).and_yield(fake_client).and_return(fake_client)
          allow(fake_client).to receive(:on_event)
          allow(fake_client).to receive(:on_error)

          client = described_class.new(uri, secret) { callback.call }

          expect(client.instance_variable_get(:@connection_attempts)).to eq(0)

          client.start

          expect(client.instance_variable_get(:@connection_attempts)).to eq(1)

          # Simulate reconnection
          client.instance_variable_set(:@closed, false)
          client.start

          expect(client.instance_variable_get(:@connection_attempts)).to eq(2)
        end

        it 'logs connection attempt with attempt number' do
          fake_client = instance_double(SSE::Client)
          allow(SSE::Client).to receive(:new).and_yield(fake_client)
          allow(fake_client).to receive(:on_event)
          allow(fake_client).to receive(:on_error)

          client = described_class.new(uri, secret) { callback.call }
          client.start

          expect(logger).to have_received(:log).with('Debug', /Connecting to.*attempt #1/)
        end

        it 'logs successful connection' do
          fake_client = instance_double(SSE::Client)
          allow(SSE::Client).to receive(:new).and_yield(fake_client)
          allow(fake_client).to receive(:on_event)
          allow(fake_client).to receive(:on_error)

          client = described_class.new(uri, secret) { callback.call }
          client.start

          expect(logger).to have_received(:log).with('Debug', '[SSE Client] Connected successfully')
        end

        it 'logs and re-raises connection errors' do
          allow(SSE::Client).to receive(:new).and_raise(StandardError, 'Connection failed')

          client = described_class.new(uri, secret) { callback.call }

          expect do
            client.start
          end.to raise_error(StandardError, 'Connection failed')

          expect(logger).to have_received(:log).with('Error', /Failed to connect.*StandardError/)
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

        it 'logs closing and closed messages' do
          fake_client = instance_double(SSE::Client, close: true)
          allow(SSE::Client).to receive(:new).and_return(fake_client)
          allow(fake_client).to receive(:on_event)
          allow(fake_client).to receive(:on_error)

          client = described_class.new(uri, secret) { callback.call }
          client.start
          client.close

          expect(logger).to have_received(:log).with('Debug', '[SSE Client] Closing connection')
          expect(logger).to have_received(:log).with('Debug', '[SSE Client] Connection closed')
        end

        it 'handles errors during close gracefully' do
          fake_client = instance_double(SSE::Client)
          allow(SSE::Client).to receive(:new).and_return(fake_client)
          allow(fake_client).to receive(:on_event)
          allow(fake_client).to receive(:on_error)
          allow(fake_client).to receive(:close).and_raise(StandardError, 'Close failed')

          client = described_class.new(uri, secret) { callback.call }
          client.start

          expect { client.close }.not_to raise_error

          expect(logger).to have_received(:log).with('Debug', /Error during close/)
        end

        it 'sets closed flag to true' do
          client = described_class.new(uri, secret) { callback.call }

          expect(client.closed).to be false

          client.close

          expect(client.closed).to be true
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

          expect(logger).to have_received(:log).with('Debug', '[SSE Client] Unknown event: FooEvent with payload: hello')
        end

        it 'logs RpcServerStop event when received' do
          client = described_class.new(uri, secret) { callback.call }

          event = Struct.new(:type, :data).new('RpcServerStop', '')
          client.send(:handle_event, event)

          expect(logger).to have_received(:log).with('Debug', '[SSE Client] RpcServerStop received')
        end

        it 'handles errors during event processing' do
          client = described_class.new(uri, secret) { callback.call }

          event = Struct.new(:type, :data).new('invalid', nil)
          allow(event).to receive(:type).and_raise(StandardError, 'Event parsing failed')

          expect { client.send(:handle_event, event) }.not_to raise_error

          expect(logger).to have_received(:log).with('Error', /Error handling event/)
        end

        it 'strips whitespace from event type and data' do
          client = described_class.new(uri, secret) { callback.call }

          event = Struct.new(:type, :data).new('  FooEvent  ', '  data  ')
          client.send(:handle_event, event)

          expect(logger).to have_received(:log).with('Debug', '[SSE Client] Unknown event: FooEvent with payload: data')
        end
      end

      describe '#handle_error' do
        it 'logs connection errors' do
          client = described_class.new(uri, secret) { callback.call }

          error = StandardError.new('Connection interrupted')
          client.send(:handle_error, error)

          expect(logger).to have_received(:log).with('Warn', /Error: StandardError - Connection interrupted/)
        end

        it 'identifies EOFError as connection lost' do
          client = described_class.new(uri, secret) { callback.call }

          error = EOFError.new
          client.send(:handle_error, error)

          expect(logger).to have_received(:log).with('Warn', /Connection lost: EOFError/)
        end

        it 'identifies IOError as connection lost' do
          client = described_class.new(uri, secret) { callback.call }

          error = IOError.new
          client.send(:handle_error, error)

          expect(logger).to have_received(:log).with('Warn', /Connection lost: IOError/)
        end

        it 'does not log errors when client is closed' do
          client = described_class.new(uri, secret) { callback.call }
          client.close

          error = StandardError.new('Error after close')
          client.send(:handle_error, error)

          expect(logger).not_to have_received(:log).with('Warn', anything)
        end
      end

      describe '#handle_rpc_stop' do
        it 'executes the callback safely' do
          client = described_class.new(uri, secret) { callback.call }

          client.send(:handle_rpc_stop)

          expect(callback).to have_received(:call)
        end

        it 'handles callback errors without crashing' do
          error_callback = proc { raise StandardError, 'Callback failed' }
          client = described_class.new(uri, secret, &error_callback)

          expect { client.send(:handle_rpc_stop) }.not_to raise_error

          expect(logger).to have_received(:log).with('Error', /Error in RPC stop callback/)
        end

        it 'handles nil callback gracefully' do
          client = described_class.new(uri, secret)

          expect { client.send(:handle_rpc_stop) }.not_to raise_error
        end
      end

      describe '#generate_signature' do
        it 'generates correct HMAC signature' do
          client = described_class.new(uri, secret) { callback.call }
          timestamp = '2025-01-01T12:00:00Z'

          signature = client.send(:generate_signature, timestamp)

          expected_signature = OpenSSL::HMAC.hexdigest('SHA256', secret, timestamp)
          expect(signature).to eq(expected_signature)
        end
      end
    end
  end
end
