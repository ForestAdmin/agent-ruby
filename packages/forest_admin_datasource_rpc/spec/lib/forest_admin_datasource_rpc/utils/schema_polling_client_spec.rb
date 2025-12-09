require 'spec_helper'

module ForestAdminDatasourceRpc
  module Utils
    describe SchemaPollingClient do
      let(:uri) { 'https://example.com' }
      let(:secret) { 'my-secret' }
      let(:logger) { instance_spy(Logger) }
      let(:callback) { instance_double(Proc, call: nil) }
      let(:schema) { { collections: [{ name: 'Products' }], charts: [] } }

      before do
        allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
      end

      describe '#initialize' do
        it 'initializes with correct attributes' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }

          expect(client.instance_variable_get(:@uri)).to eq(uri)
          expect(client.instance_variable_get(:@auth_secret)).to eq(secret)
          expect(client.instance_variable_get(:@closed)).to be false
          expect(client.instance_variable_get(:@last_schema_hash)).to be_nil
          expect(client.instance_variable_get(:@polling_thread)).to be_nil
          expect(client.instance_variable_get(:@connection_attempts)).to eq(0)
        end

        it 'uses default polling interval of 600s (10 minutes)' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }

          expect(client.instance_variable_get(:@polling_interval)).to eq(600)
        end

        it 'accepts custom polling interval' do
          client = described_class.new(uri, secret, polling_interval: 120) { |schema| callback.call(schema) }

          expect(client.instance_variable_get(:@polling_interval)).to eq(120)
        end

        it 'exposes closed status via attr_reader' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }

          expect(client.closed).to be false

          client.stop

          expect(client.closed).to be true
        end

        it 'creates HTTP client with timeouts' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }

          # Verify HTTP client was created via Faraday
          expect(client.instance_variable_get(:@http_client)).to be_a(Faraday::Connection)
        end
      end

      describe '#start' do
        it 'starts the polling thread' do
          client = described_class.new(uri, secret, polling_interval: 1) { |schema| callback.call(schema) }

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
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          client.stop

          client.start

          expect(client.instance_variable_get(:@polling_thread)).to be_nil
        end

        it 'does not create duplicate thread if already running' do
          client = described_class.new(uri, secret, polling_interval: 1) { |schema| callback.call(schema) }

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
          client = described_class.new(uri, secret, polling_interval: 1) { |schema| callback.call(schema) }

          allow(client).to receive(:polling_loop) do
            sleep(10) unless client.closed
          end

          client.start
          sleep(0.05)

          expect(logger).to have_received(:log).with('Debug', '[Schema Polling] Polling started')

          client.stop
        end
      end

      describe '#stop' do
        it 'stops the polling thread' do
          client = described_class.new(uri, secret, polling_interval: 1) { |schema| callback.call(schema) }

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
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }

          expect { client.stop }.not_to raise_error
          expect { client.stop }.not_to raise_error
        end

        it 'sets closed flag' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }

          expect(client.closed).to be false

          client.stop

          expect(client.closed).to be true
        end

        it 'logs stopping and stopped messages' do
          client = described_class.new(uri, secret, polling_interval: 1) { |schema| callback.call(schema) }

          allow(client).to receive(:polling_loop) do
            sleep(10) unless client.closed
          end

          client.start
          sleep(0.05)

          client.stop

          expect(logger).to have_received(:log).with('Debug', '[Schema Polling] Stopping polling')
          expect(logger).to have_received(:log).with('Debug', '[Schema Polling] Polling stopped')
        end
      end

      describe '#check_schema' do
        let(:http_client) { instance_double(Faraday::Connection) }
        let(:success_response) do
          instance_double(
            Faraday::Response,
            success?: true,
            status: 200,
            body: JSON.generate(schema)
          )
        end

        it 'makes GET request to /forest/rpc-schema with HMAC headers' do
          timestamp = '2025-01-01T12:00:00.000Z'
          signature = OpenSSL::HMAC.hexdigest('SHA256', secret, timestamp)
          allow(Time).to receive(:now).and_return(Time.parse(timestamp))

          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          client.instance_variable_set(:@http_client, http_client)
          allow(http_client).to receive(:get).and_return(success_response)

          client.send(:check_schema)

          expect(http_client).to have_received(:get).with(
            "#{uri}/forest/rpc-schema",
            nil,
            {
              'X_TIMESTAMP' => timestamp,
              'X_SIGNATURE' => signature
            }
          )
        end

        it 'stores hash on first poll without triggering callback' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          client.instance_variable_set(:@http_client, http_client)
          allow(http_client).to receive(:get).and_return(success_response)

          client.send(:check_schema)

          expect(client.instance_variable_get(:@last_schema_hash)).not_to be_nil
          expect(callback).not_to have_received(:call)
          expect(logger).to have_received(:log).with('Debug', '[Schema Polling] Initial schema hash stored')
        end

        it 'detects schema change and triggers callback with new schema' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          client.instance_variable_set(:@http_client, http_client)

          # First poll
          allow(http_client).to receive(:get).and_return(success_response)
          client.send(:check_schema)

          # Second poll with different schema
          new_schema = { collections: [{ name: 'Orders' }], charts: [] }
          new_response = instance_double(
            Faraday::Response,
            success?: true,
            status: 200,
            body: JSON.generate(new_schema)
          )
          allow(http_client).to receive(:get).and_return(new_response)

          client.send(:check_schema)

          # Callback should have been called with new schema
          expect(callback).to have_received(:call).with(new_schema)
          expect(logger).to have_received(:log).with('Info', /Schema changed detected/)
        end

        it 'does not trigger callback if schema unchanged' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          client.instance_variable_set(:@http_client, http_client)
          allow(http_client).to receive(:get).and_return(success_response)

          # First poll
          client.send(:check_schema)

          # Second poll with same schema
          client.send(:check_schema)

          # Callback should not have been called (only once for first poll setup)
          expect(callback).not_to have_received(:call)
          expect(logger).to have_received(:log).with('Debug', '[Schema Polling] Schema unchanged')
        end

        it 'handles HTTP errors gracefully' do
          error_response = instance_double(
            Faraday::Response,
            success?: false,
            status: 500,
            body: 'Internal Server Error'
          )
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          client.instance_variable_set(:@http_client, http_client)
          allow(http_client).to receive(:get).and_return(error_response)

          expect { client.send(:check_schema) }.not_to raise_error

          expect(logger).to have_received(:log).with('Warn', /HTTP 500/)
          expect(callback).not_to have_received(:call)
        end

        it 'handles connection failures gracefully' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          client.instance_variable_set(:@http_client, http_client)
          allow(http_client).to receive(:get).and_raise(Faraday::ConnectionFailed, 'Connection refused')

          expect { client.send(:check_schema) }.not_to raise_error

          expect(logger).to have_received(:log).with('Warn', /Connection error/)
          expect(callback).not_to have_received(:call)
        end

        it 'handles timeout errors gracefully' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          client.instance_variable_set(:@http_client, http_client)
          allow(http_client).to receive(:get).and_raise(Faraday::TimeoutError, 'Timeout')

          expect { client.send(:check_schema) }.not_to raise_error

          expect(logger).to have_received(:log).with('Warn', /Connection error/)
        end

        it 'handles invalid JSON gracefully' do
          invalid_response = instance_double(
            Faraday::Response,
            success?: true,
            status: 200,
            body: 'not json'
          )
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          client.instance_variable_set(:@http_client, http_client)
          allow(http_client).to receive(:get).and_return(invalid_response)

          expect { client.send(:check_schema) }.not_to raise_error

          expect(logger).to have_received(:log).with('Error', /Invalid JSON/)
        end

        it 'increments and resets connection attempts on successful poll' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          client.instance_variable_set(:@http_client, http_client)
          allow(http_client).to receive(:get).and_return(success_response)

          # Connection attempts should be incremented then reset
          client.send(:check_schema)

          # After successful poll, connection attempts is reset to 0
          expect(client.instance_variable_get(:@connection_attempts)).to eq(0)
        end
      end

      describe '#trigger_schema_change_callback' do
        it 'executes the callback with schema' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }

          client.send(:trigger_schema_change_callback, schema)

          expect(callback).to have_received(:call).with(schema)
        end

        it 'handles callback errors without crashing' do
          error_callback = proc { |_schema| raise StandardError, 'Callback failed' }
          client = described_class.new(uri, secret, &error_callback)

          expect { client.send(:trigger_schema_change_callback, schema) }.not_to raise_error

          expect(logger).to have_received(:log).with('Error', /Error in schema change callback/)
        end

        it 'handles nil callback gracefully' do
          client = described_class.new(uri, secret)

          expect { client.send(:trigger_schema_change_callback, schema) }.not_to raise_error
        end
      end

      describe '#generate_signature' do
        it 'generates correct HMAC signature' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          timestamp = '2025-01-01T12:00:00Z'

          signature = client.send(:generate_signature, timestamp)

          expected_signature = OpenSSL::HMAC.hexdigest('SHA256', secret, timestamp)
          expect(signature).to eq(expected_signature)
        end
      end

      describe 'integration: polling loop' do
        it 'polls at configured interval' do
          client = described_class.new(uri, secret, polling_interval: 0.15) { |schema| callback.call(schema) }

          check_count = 0
          allow(client).to receive(:check_schema) do
            check_count += 1
          end

          client.start
          sleep(0.5) # Should perform ~3 checks (0s, 0.15s, 0.30s)
          client.stop

          expect(check_count).to be >= 2
          expect(check_count).to be <= 5
        end

        it 'triggers callback on schema change' do
          client = described_class.new(uri, secret, polling_interval: 0.1) { |schema| callback.call(schema) }

          http_client = instance_double(Faraday::Connection)
          client.instance_variable_set(:@http_client, http_client)

          # First poll
          schema1 = { collections: [{ name: 'Products' }] }
          response1 = instance_double(Faraday::Response, success?: true, status: 200, body: JSON.generate(schema1))

          # Second poll with different schema
          schema2 = { collections: [{ name: 'Orders' }] }
          response2 = instance_double(Faraday::Response, success?: true, status: 200, body: JSON.generate(schema2))

          allow(http_client).to receive(:get).and_return(response1, response2)

          client.start
          sleep(0.3) # Wait for 2-3 polls
          client.stop

          # Should have been called with the changed schema
          expect(callback).to have_received(:call).with(schema2).at_least(:once)
        end

        it 'does not trigger callback if schema stays the same' do
          client = described_class.new(uri, secret, polling_interval: 0.1) { |schema| callback.call(schema) }

          http_client = instance_double(Faraday::Connection)
          client.instance_variable_set(:@http_client, http_client)

          # Same schema for all polls
          response = instance_double(Faraday::Response, success?: true, status: 200, body: JSON.generate(schema))
          allow(http_client).to receive(:get).and_return(response)

          client.start
          sleep(0.3) # Wait for 2-3 polls
          client.stop

          # Should NOT have called callback (schema unchanged)
          expect(callback).not_to have_received(:call)
        end

        it 'continues polling after connection errors' do
          client = described_class.new(uri, secret, polling_interval: 0.1) { |schema| callback.call(schema) }

          http_client = instance_double(Faraday::Connection)
          client.instance_variable_set(:@http_client, http_client)

          # First poll fails, second succeeds
          schema_response = instance_double(Faraday::Response, success?: true, status: 200, body: JSON.generate(schema))
          call_count = 0
          allow(http_client).to receive(:get) do
            call_count += 1
            raise Faraday::ConnectionFailed if call_count == 1
            schema_response
          end

          client.start
          sleep(0.3) # Wait for 2-3 polls
          client.stop

          # Should have continued polling after failure
          expect(logger).to have_received(:log).with('Warn', /Connection error/)
          expect(logger).to have_received(:log).with('Debug', /Initial schema hash stored/)
        end

        it 'stops polling when closed' do
          client = described_class.new(uri, secret, polling_interval: 0.1) { |schema| callback.call(schema) }

          check_count = 0
          allow(client).to receive(:check_schema) do
            check_count += 1
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
