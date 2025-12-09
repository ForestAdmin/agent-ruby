require 'spec_helper'

module ForestAdminDatasourceRpc
  module Utils
    describe HealthCheckClient do
      let(:uri) { 'https://example.com/forest/health' }
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
          expect(client.instance_variable_get(:@consecutive_failures)).to eq(0)
          expect(client.instance_variable_get(:@polling_thread)).to be_nil
          expect(client.instance_variable_get(:@server_down_triggered)).to be false
          expect(client.instance_variable_get(:@connection_attempts)).to eq(0)
        end

        it 'uses default polling interval' do
          client = described_class.new(uri, secret) { callback.call }

          expect(client.instance_variable_get(:@polling_interval)).to eq(30)
        end

        it 'uses default failure threshold' do
          client = described_class.new(uri, secret) { callback.call }

          expect(client.instance_variable_get(:@failure_threshold)).to eq(3)
        end

        it 'accepts custom polling interval' do
          client = described_class.new(uri, secret, polling_interval: 10) { callback.call }

          expect(client.instance_variable_get(:@polling_interval)).to eq(10)
        end

        it 'accepts custom failure threshold' do
          client = described_class.new(uri, secret, failure_threshold: 5) { callback.call }

          expect(client.instance_variable_get(:@failure_threshold)).to eq(5)
        end

        it 'exposes closed status via attr_reader' do
          client = described_class.new(uri, secret) { callback.call }

          expect(client.closed).to be false

          client.stop

          expect(client.closed).to be true
        end

        it 'creates HTTP client with timeouts' do
          client = described_class.new(uri, secret) { callback.call }

          # Verify HTTP client was created via Faraday
          expect(client.instance_variable_get(:@http_client)).to be_a(Faraday::Connection)
        end
      end

      describe '#start' do
        it 'starts the polling thread' do
          client = described_class.new(uri, secret, polling_interval: 1) { callback.call }

          # Stub polling_loop to keep thread alive without making HTTP calls
          allow(client).to receive(:polling_loop) do
            sleep(10) unless client.closed # Sleep until stopped
          end

          client.start
          sleep(0.05)

          expect(client.instance_variable_get(:@polling_thread)).to be_alive

          client.stop
        end

        it 'does not start if already closed' do
          client = described_class.new(uri, secret) { callback.call }
          client.stop

          client.start

          expect(client.instance_variable_get(:@polling_thread)).to be_nil
        end

        it 'does not create duplicate thread if already running' do
          client = described_class.new(uri, secret, polling_interval: 1) { callback.call }

          # Stub polling_loop to keep thread alive
          allow(client).to receive(:polling_loop) do
            sleep(10) unless client.closed
          end

          client.start
          sleep(0.05)

          first_thread = client.instance_variable_get(:@polling_thread)
          client.start
          second_thread = client.instance_variable_get(:@polling_thread)

          expect(first_thread).to eq(second_thread)
          expect(first_thread).to be_alive

          client.stop
        end

        it 'logs polling started' do
          client = described_class.new(uri, secret, polling_interval: 1) { callback.call }

          allow(client).to receive(:polling_loop) do
            sleep(10) unless client.closed
          end

          client.start
          sleep(0.05)

          expect(logger).to have_received(:log).with('Debug', '[Health Check] Polling started')

          client.stop
        end
      end

      describe '#stop' do
        it 'stops the polling thread' do
          client = described_class.new(uri, secret, polling_interval: 1) { callback.call }

          # Stub polling_loop to keep thread alive
          allow(client).to receive(:polling_loop) do
            sleep(10) unless client.closed
          end

          client.start
          sleep(0.05)

          expect(client.instance_variable_get(:@polling_thread)).to be_alive

          client.stop

          sleep(0.05)
          expect(client.instance_variable_get(:@polling_thread)).to be_nil
        end

        it 'is idempotent' do
          client = described_class.new(uri, secret) { callback.call }

          expect { client.stop }.not_to raise_error
          expect { client.stop }.not_to raise_error
        end

        it 'sets closed flag' do
          client = described_class.new(uri, secret) { callback.call }

          expect(client.closed).to be false

          client.stop

          expect(client.closed).to be true
        end

        it 'logs stopping and stopped messages' do
          client = described_class.new(uri, secret, polling_interval: 0.1) { callback.call }
          client.start
          sleep(0.05)

          client.stop

          expect(logger).to have_received(:log).with('Debug', '[Health Check] Stopping polling')
          expect(logger).to have_received(:log).with('Debug', '[Health Check] Polling stopped')
        end
      end

      describe '#check_health' do
        let(:http_client) { instance_double(Faraday::Connection) }
        let(:success_response) do
          instance_double(Faraday::Response, success?: true, status: 200, body: '{"status":"ok","version":"1.0.0"}')
        end

        it 'makes GET request with HMAC headers' do
          timestamp = '2025-01-01T12:00:00.000Z'
          signature = OpenSSL::HMAC.hexdigest('SHA256', secret, timestamp)
          allow(Time).to receive(:now).and_return(Time.parse(timestamp))

          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@http_client, http_client)
          allow(http_client).to receive(:get).and_return(success_response)

          client.send(:check_health)

          expect(http_client).to have_received(:get).with(
            uri,
            nil,
            {
              'X_TIMESTAMP' => timestamp,
              'X_SIGNATURE' => signature
            }
          )
        end

        it 'returns true for successful response with ok status' do
          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@http_client, http_client)
          allow(http_client).to receive(:get).and_return(success_response)

          result = client.send(:check_health)

          expect(result).to be true
        end

        it 'returns false for non-ok status in response' do
          bad_response = instance_double(
            Faraday::Response,
            success?: true,
            status: 200,
            body: '{"status":"error"}'
          )
          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@http_client, http_client)
          allow(http_client).to receive(:get).and_return(bad_response)

          result = client.send(:check_health)

          expect(result).to be false
        end

        it 'returns false for non-successful HTTP status' do
          error_response = instance_double(
            Faraday::Response,
            success?: false,
            status: 500,
            body: 'Internal Server Error'
          )
          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@http_client, http_client)
          allow(http_client).to receive(:get).and_return(error_response)

          result = client.send(:check_health)

          expect(result).to be false
        end

        it 'returns false for connection errors' do
          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@http_client, http_client)
          allow(http_client).to receive(:get).and_raise(Faraday::ConnectionFailed, 'Connection refused')

          result = client.send(:check_health)

          expect(result).to be false
        end

        it 'returns false for timeout errors' do
          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@http_client, http_client)
          allow(http_client).to receive(:get).and_raise(Faraday::TimeoutError, 'Timeout')

          result = client.send(:check_health)

          expect(result).to be false
        end

        it 'returns false for invalid JSON' do
          invalid_response = instance_double(
            Faraday::Response,
            success?: true,
            status: 200,
            body: 'not json'
          )
          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@http_client, http_client)
          allow(http_client).to receive(:get).and_return(invalid_response)

          result = client.send(:check_health)

          expect(result).to be false
        end

        it 'increments connection attempts' do
          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@http_client, http_client)
          allow(http_client).to receive(:get).and_return(success_response)

          expect do
            client.send(:check_health)
          end.to change { client.instance_variable_get(:@connection_attempts) }.from(0).to(1)
        end

        it 'logs successful health check with version' do
          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@http_client, http_client)
          allow(http_client).to receive(:get).and_return(success_response)

          client.send(:check_health)

          expect(logger).to have_received(:log).with('Debug', /Health check successful \(version: 1.0.0\)/)
        end

        it 'logs connection errors as Debug' do
          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@http_client, http_client)
          allow(http_client).to receive(:get).and_raise(Faraday::ConnectionFailed)

          client.send(:check_health)

          expect(logger).to have_received(:log).with('Debug', /Connection error/)
        end

        it 'logs HTTP errors as Warn' do
          error_response = instance_double(
            Faraday::Response,
            success?: false,
            status: 500,
            body: 'Error'
          )
          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@http_client, http_client)
          allow(http_client).to receive(:get).and_return(error_response)

          client.send(:check_health)

          expect(logger).to have_received(:log).with('Warn', /HTTP 500/)
        end
      end

      describe '#handle_success' do
        it 'resets consecutive failures' do
          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@consecutive_failures, 3)

          client.send(:handle_success)

          expect(client.instance_variable_get(:@consecutive_failures)).to eq(0)
        end

        it 'resets server down triggered flag' do
          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@server_down_triggered, true)

          client.send(:handle_success)

          expect(client.instance_variable_get(:@server_down_triggered)).to be false
        end

        it 'resets connection attempts' do
          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@connection_attempts, 5)

          client.send(:handle_success)

          expect(client.instance_variable_get(:@connection_attempts)).to eq(0)
        end

        it 'logs server back online if there were previous failures' do
          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@consecutive_failures, 2)

          client.send(:handle_success)

          expect(logger).to have_received(:log).with('Info', '[Health Check] Server is back online')
        end

        it 'does not log if no previous failures' do
          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@consecutive_failures, 0)

          client.send(:handle_success)

          expect(logger).not_to have_received(:log).with('Info', /back online/)
        end
      end

      describe '#handle_failure' do
        it 'increments consecutive failures' do
          client = described_class.new(uri, secret) { callback.call }

          expect do
            client.send(:handle_failure)
          end.to change { client.instance_variable_get(:@consecutive_failures) }.from(0).to(1)
        end

        it 'logs failure count' do
          client = described_class.new(uri, secret, failure_threshold: 3) { callback.call }

          client.send(:handle_failure)

          expect(logger).to have_received(:log).with('Warn', /Health check failed \(1\/3\)/)
        end

        it 'triggers callback when threshold is reached' do
          client = described_class.new(uri, secret, failure_threshold: 3) { callback.call }
          client.instance_variable_set(:@consecutive_failures, 2)

          client.send(:handle_failure)

          expect(callback).to have_received(:call)
        end

        it 'does not trigger callback multiple times' do
          client = described_class.new(uri, secret, failure_threshold: 3) { callback.call }
          client.instance_variable_set(:@consecutive_failures, 2)

          client.send(:handle_failure) # Should trigger
          client.send(:handle_failure) # Should not trigger again

          expect(callback).to have_received(:call).once
        end

        it 'sets server down triggered flag' do
          client = described_class.new(uri, secret, failure_threshold: 3) { callback.call }
          client.instance_variable_set(:@consecutive_failures, 2)

          client.send(:handle_failure)

          expect(client.instance_variable_get(:@server_down_triggered)).to be true
        end
      end

      describe '#trigger_server_down_callback' do
        it 'executes the callback' do
          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@consecutive_failures, 3)

          client.send(:trigger_server_down_callback)

          expect(callback).to have_received(:call)
        end

        it 'handles callback errors without crashing' do
          error_callback = proc { raise StandardError, 'Callback failed' }
          client = described_class.new(uri, secret, &error_callback)
          client.instance_variable_set(:@consecutive_failures, 3)

          expect { client.send(:trigger_server_down_callback) }.not_to raise_error

          expect(logger).to have_received(:log).with('Error', /Error in server down callback/)
        end

        it 'handles nil callback gracefully' do
          client = described_class.new(uri, secret)
          client.instance_variable_set(:@consecutive_failures, 3)

          expect { client.send(:trigger_server_down_callback) }.not_to raise_error
        end

        it 'logs server down warning' do
          client = described_class.new(uri, secret) { callback.call }
          client.instance_variable_set(:@consecutive_failures, 3)

          client.send(:trigger_server_down_callback)

          expect(logger).to have_received(:log).with(
            'Warn',
            '[Health Check] Server appears to be down after 3 consecutive failures'
          )
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

      describe 'integration: polling loop' do
        it 'polls at configured interval' do
          client = described_class.new(uri, secret, polling_interval: 0.15, failure_threshold: 5) { callback.call }

          check_count = 0
          allow(client).to receive(:check_health) do
            check_count += 1
            true
          end

          client.start
          sleep(0.5) # Should perform ~3 checks (0s, 0.15s, 0.30s)
          client.stop

          expect(check_count).to be >= 2
          expect(check_count).to be <= 5
        end

        it 'triggers callback after threshold failures' do
          client = described_class.new(uri, secret, polling_interval: 0.1, failure_threshold: 2) { callback.call }

          allow(client).to receive(:check_health).and_return(false)

          client.start
          sleep(0.4) # Wait for at least 3 checks with 2 failures threshold
          client.stop

          expect(callback).to have_received(:call).at_least(:once)
        end

        it 'does not trigger callback before threshold' do
          client = described_class.new(uri, secret, polling_interval: 0.1, failure_threshold: 5) { callback.call }

          allow(client).to receive(:check_health).and_return(false)

          client.start
          sleep(0.25) # Only 1-2 failures
          client.stop

          expect(callback).not_to have_received(:call)
        end

        it 'resets failures on successful check after failures' do
          client = described_class.new(uri, secret, polling_interval: 0.1, failure_threshold: 3) { callback.call }

          call_count = 0
          allow(client).to receive(:check_health) do
            call_count += 1
            # First 2 calls fail, then succeed
            call_count > 2
          end

          client.start
          sleep(0.35)
          client.stop

          # Should not trigger callback because success reset the counter
          expect(callback).not_to have_received(:call)
        end

        it 'stops polling when closed' do
          client = described_class.new(uri, secret, polling_interval: 0.1) { callback.call }

          check_count = 0
          allow(client).to receive(:check_health) do
            check_count += 1
            true
          end

          client.start
          sleep(0.15)
          client.stop
          checks_at_stop = check_count

          sleep(0.2) # Wait more time

          # Should not have increased after stop
          expect(check_count).to eq(checks_at_stop)
        end
      end
    end
  end
end
