require 'spec_helper'

module ForestAdminDatasourceRpc
  module Utils
    describe SseClient do
      let(:uri) { 'https://example.com/sse' }
      let(:secret) { 'my-secret' }
      let(:logger) { instance_spy(Logger) }
      let(:callback) { instance_double(Proc, call: nil) }

      before do
        allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
      end

      describe '#initialize' do
        it 'initializes with correct attributes' do
          client = described_class.new(uri, secret) { callback.call }

          expect(client.instance_variable_get(:@uri)).to eq(uri)
          expect(client.instance_variable_get(:@auth_secret)).to eq(secret)
          expect(client.instance_variable_get(:@closed)).to be false
          expect(client.instance_variable_get(:@connection_attempts)).to eq(0)
          expect(client.instance_variable_get(:@connecting)).to be false
          expect(client.instance_variable_get(:@reconnect_thread)).to be_nil
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
          fake_client = instance_double(SSE::Client, close: true)
          allow(SSE::Client).to receive(:new).and_yield(fake_client).and_return(fake_client)
          allow(fake_client).to receive(:on_event)
          allow(fake_client).to receive(:on_error)

          client = described_class.new(uri, secret) { callback.call }

          expect(client.instance_variable_get(:@connection_attempts)).to eq(0)

          client.start

          expect(client.instance_variable_get(:@connection_attempts)).to eq(1)

          # Simulate reconnection - reset both closed and connecting flags
          client.instance_variable_set(:@closed, false)
          client.instance_variable_set(:@connecting, false)
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

        it 'logs connection errors and schedules reconnect' do
          allow(SSE::Client).to receive(:new).and_raise(StandardError, 'Connection failed')
          allow(Thread).to receive(:new)

          client = described_class.new(uri, secret) { callback.call }

          expect do
            client.start
          end.not_to raise_error

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

        it 'stops reconnection thread if running' do
          fake_client = instance_double(SSE::Client, close: true)
          fake_thread = instance_double(Thread, alive?: true, kill: nil)
          allow(SSE::Client).to receive(:new).and_return(fake_client)
          allow(fake_client).to receive(:on_event)
          allow(fake_client).to receive(:on_error)

          client = described_class.new(uri, secret) { callback.call }
          client.start
          client.instance_variable_set(:@reconnect_thread, fake_thread)

          client.close

          expect(fake_thread).to have_received(:kill)
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

        it 'resets connecting flag and connection attempts on first heartbeat' do
          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@connecting, true)
          client.instance_variable_set(:@connection_attempts, 3)

          event = Struct.new(:type, :data).new('heartbeat', '')
          client.send(:handle_event, event)

          expect(client.instance_variable_get(:@connecting)).to be false
          expect(client.instance_variable_get(:@connection_attempts)).to eq(0)
          expect(logger).to have_received(:log).with('Debug', '[SSE Client] Connection stable')
        end

        it 'does not log connection stable if not connecting' do
          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@connecting, false)

          event = Struct.new(:type, :data).new('heartbeat', '')
          client.send(:handle_event, event)

          expect(logger).not_to have_received(:log).with('Debug', '[SSE Client] Connection stable')
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

      describe '#handle_error_with_reconnect' do
        before do
          allow(Thread).to receive(:new)
        end

        it 'logs connection errors' do
          client = described_class.new(uri, secret) { callback.call }

          error = StandardError.new('Connection interrupted')
          client.send(:handle_error_with_reconnect, error)

          expect(logger).to have_received(:log).with('Warn', /Error: StandardError - Connection interrupted/)
        end

        it 'identifies EOFError as connection lost and logs as Debug' do
          client = described_class.new(uri, secret) { callback.call }

          error = EOFError.new
          client.send(:handle_error_with_reconnect, error)

          expect(logger).to have_received(:log).with('Debug', /Connection lost: EOFError/)
        end

        it 'identifies IOError as connection lost and logs as Debug' do
          client = described_class.new(uri, secret) { callback.call }

          error = IOError.new
          client.send(:handle_error_with_reconnect, error)

          expect(logger).to have_received(:log).with('Debug', /Connection lost: IOError/)
        end

        it 'does not log errors when client is closed' do
          client = described_class.new(uri, secret) { callback.call }
          client.close

          error = StandardError.new('Error after close')
          client.send(:handle_error_with_reconnect, error)

          expect(logger).not_to have_received(:log).with('Warn', anything)
          expect(logger).not_to have_received(:log).with('Debug', /Error/)
        end

        it 'closes the client and schedules reconnect' do
          fake_client = instance_double(SSE::Client, close: true)
          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@client, fake_client)

          error = StandardError.new('Connection error')
          client.send(:handle_error_with_reconnect, error)

          expect(fake_client).to have_received(:close)
          expect(Thread).to have_received(:new)
        end

        it 'handles HTTP auth errors with Debug log level' do
          # rubocop:disable RSpec/VerifiedDoubles
          # Using regular double to mock SSE::Errors::HTTPStatusError for case statement matching
          auth_error = double(
            'HTTPStatusError',
            status: 401,
            body: 'Unauthorized',
            respond_to?: true
          )
          # rubocop:enable RSpec/VerifiedDoubles
          # Make the case statement match this error as HTTPStatusError
          allow(SSE::Errors::HTTPStatusError).to receive(:===).with(auth_error).and_return(true)

          client = described_class.new(uri, secret) { callback.call }
          client.send(:handle_error_with_reconnect, auth_error)

          expect(logger).to have_received(:log).with('Debug', /HTTP 401/)
        end
      end

      describe '#schedule_reconnect' do
        it 'creates a new thread that waits and reconnects' do
          fake_thread = instance_double(Thread, alive?: false)
          client = described_class.new(uri, secret) { callback.call }

          allow(Thread).to receive(:new).and_yield.and_return(fake_thread)
          allow(client).to receive(:sleep)
          allow(client).to receive(:attempt_connection)

          client.send(:schedule_reconnect)

          expect(Thread).to have_received(:new)
        end

        it 'does not create a new thread if one is already running' do
          fake_thread = instance_double(Thread, alive?: true)
          allow(Thread).to receive(:new).and_return(fake_thread)

          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@reconnect_thread, fake_thread)

          client.send(:schedule_reconnect)

          expect(Thread).not_to have_received(:new)
        end

        it 'does not schedule reconnect if client is closed' do
          allow(Thread).to receive(:new)

          client = described_class.new(uri, secret) { callback.call }
          client.close

          client.send(:schedule_reconnect)

          expect(Thread).not_to have_received(:new)
        end
      end

      describe '#calculate_backoff_delay' do
        it 'calculates exponential backoff delay' do
          client = described_class.new(uri, secret) { callback.call }

          client.instance_variable_set(:@connection_attempts, 1)
          expect(client.send(:calculate_backoff_delay)).to eq(2)

          client.instance_variable_set(:@connection_attempts, 2)
          expect(client.send(:calculate_backoff_delay)).to eq(4)

          client.instance_variable_set(:@connection_attempts, 3)
          expect(client.send(:calculate_backoff_delay)).to eq(8)

          client.instance_variable_set(:@connection_attempts, 4)
          expect(client.send(:calculate_backoff_delay)).to eq(16)
        end

        it 'caps delay at MAX_BACKOFF_DELAY' do
          client = described_class.new(uri, secret) { callback.call }

          client.instance_variable_set(:@connection_attempts, 10)
          expect(client.send(:calculate_backoff_delay)).to eq(30)
        end
      end

      describe '#attempt_connection' do
        it 'does not attempt connection if already connecting' do
          allow(SSE::Client).to receive(:new)

          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@connecting, true)

          client.send(:attempt_connection)

          expect(SSE::Client).not_to have_received(:new)
        end

        it 'closes existing client before creating new connection' do
          old_client = instance_double(SSE::Client, close: true)
          allow(SSE::Client).to receive(:new).and_yield(instance_double(SSE::Client, on_event: nil, on_error: nil))

          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@client, old_client)

          client.send(:attempt_connection)

          expect(old_client).to have_received(:close)
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
