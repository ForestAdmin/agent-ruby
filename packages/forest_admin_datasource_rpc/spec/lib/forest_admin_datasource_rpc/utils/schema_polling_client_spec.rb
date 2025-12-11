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
          expect(client.instance_variable_get(:@cached_etag)).to be_nil
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

        it 'creates RPC client for schema fetching' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }

          # Verify RPC client was created
          expect(client.instance_variable_get(:@rpc_client)).to be_a(RpcClient)
        end

        context 'when validating polling interval' do
          it 'raises error if interval is too short (< 1s)' do
            expect do
              described_class.new(uri, secret, polling_interval: 0.5) { |schema| callback.call(schema) }
            end.to raise_error(ArgumentError, /too short.*minimum: 1s/)
          end

          it 'raises error if interval is too long (> 3600s)' do
            expect do
              described_class.new(uri, secret, polling_interval: 3601) { |schema| callback.call(schema) }
            end.to raise_error(ArgumentError, /too long.*maximum: 3600s/)
          end

          it 'accepts minimum valid interval (1s)' do
            expect do
              described_class.new(uri, secret, polling_interval: 1) { |schema| callback.call(schema) }
            end.not_to raise_error
          end

          it 'accepts maximum valid interval (3600s)' do
            expect do
              described_class.new(uri, secret, polling_interval: 3600) { |schema| callback.call(schema) }
            end.not_to raise_error
          end
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

          expect(logger).to have_received(:log).with('Info', '[Schema Polling] Polling started (interval: 1s)')

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
        let(:rpc_client) { instance_double(RpcClient) }
        let(:schema_response) do
          instance_double(
            SchemaResponse,
            body: schema,
            etag: 'etag-123'
          )
        end

        before do
          allow(RpcClient).to receive(:new).and_return(rpc_client)
        end

        it 'uses RpcClient to fetch schema with ETag support' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          allow(rpc_client).to receive(:fetch_schema).and_return(schema_response)

          client.send(:check_schema)

          expect(rpc_client).to have_received(:fetch_schema).with('/forest/rpc-schema', if_none_match: nil)
        end

        it 'stores ETag on first poll without triggering callback' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          allow(rpc_client).to receive(:fetch_schema).and_return(schema_response)

          client.send(:check_schema)

          expect(client.instance_variable_get(:@cached_etag)).to eq('etag-123')
          expect(callback).not_to have_received(:call)
          expect(logger).to have_received(:log).with('Debug', '[Schema Polling] Initial schema loaded successfully (ETag: etag-123)')
        end

        it 'sends If-None-Match header on subsequent polls' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          allow(rpc_client).to receive(:fetch_schema).and_return(schema_response)

          # First poll
          client.send(:check_schema)

          # Second poll should include cached ETag
          allow(rpc_client).to receive(:fetch_schema).and_return(RpcClient::NotModified)
          client.send(:check_schema)

          expect(rpc_client).to have_received(:fetch_schema).with('/forest/rpc-schema', if_none_match: 'etag-123')
        end

        it 'detects schema change via ETag and triggers callback' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          allow(rpc_client).to receive(:fetch_schema).and_return(schema_response)

          # First poll
          client.send(:check_schema)

          # Second poll with different ETag (schema changed)
          new_schema = { collections: [{ name: 'Orders' }], charts: [] }
          new_response = instance_double(
            SchemaResponse,
            body: new_schema,
            etag: 'etag-456'
          )
          allow(rpc_client).to receive(:fetch_schema).and_return(new_response)

          client.send(:check_schema)

          # Callback should have been called with new schema
          expect(callback).to have_received(:call).with(new_schema)
          expect(logger).to have_received(:log).with('Info', /Schema changed detected/)
          expect(client.instance_variable_get(:@cached_etag)).to eq('etag-456')
        end

        it 'handles NotModified (304) response without triggering callback' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          allow(rpc_client).to receive(:fetch_schema).and_return(schema_response)

          # First poll
          client.send(:check_schema)

          # Second poll with 304 Not Modified
          allow(rpc_client).to receive(:fetch_schema).and_return(RpcClient::NotModified)
          client.send(:check_schema)

          # Callback should not have been called
          expect(callback).not_to have_received(:call)
          expect(logger).to have_received(:log).with('Debug', '[Schema Polling] Schema unchanged (HTTP 304 Not Modified), ETag still valid: etag-123')
        end

        it 'handles connection failures gracefully' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          allow(rpc_client).to receive(:fetch_schema).and_raise(Faraday::ConnectionFailed, 'Connection refused')

          expect { client.send(:check_schema) }.not_to raise_error

          expect(logger).to have_received(:log).with('Warn', /Connection error/)
          expect(callback).not_to have_received(:call)
        end

        it 'handles timeout errors gracefully' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          allow(rpc_client).to receive(:fetch_schema).and_raise(Faraday::TimeoutError, 'Timeout')

          expect { client.send(:check_schema) }.not_to raise_error

          expect(logger).to have_received(:log).with('Warn', /Connection error/)
        end

        it 'handles authentication errors gracefully' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          allow(rpc_client).to receive(:fetch_schema).and_raise(
            ForestAdminAgent::Http::Exceptions::AuthenticationOpenIdClient, 'Auth failed'
          )

          expect { client.send(:check_schema) }.not_to raise_error

          expect(logger).to have_received(:log).with('Error', /Authentication error/)
        end

        it 'handles unexpected errors gracefully' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          allow(rpc_client).to receive(:fetch_schema).and_raise(StandardError, 'Unexpected error')

          expect { client.send(:check_schema) }.not_to raise_error

          expect(logger).to have_received(:log).with('Error', /Unexpected error/)
        end

        it 'increments and resets connection attempts on successful poll' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          allow(rpc_client).to receive(:fetch_schema).and_return(schema_response)

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

      describe 'integration: polling loop' do
        it 'polls at configured interval' do
          client = described_class.new(uri, secret, polling_interval: 1) { |schema| callback.call(schema) }

          check_count = 0
          allow(client).to receive(:check_schema) do
            check_count += 1
          end

          client.start
          sleep(0.5) # Should perform at least 1 check
          client.stop

          expect(check_count).to be >= 1
          expect(check_count).to be <= 3
        end

        it 'triggers callback on schema change' do
          rpc_client = instance_double(RpcClient)
          allow(RpcClient).to receive(:new).and_return(rpc_client)

          client = described_class.new(uri, secret, polling_interval: 1) { |schema| callback.call(schema) }

          # First poll
          schema1 = { collections: [{ name: 'Products' }] }
          response1 = instance_double(SchemaResponse, body: schema1, etag: 'etag-1')

          # Second poll with different schema
          schema2 = { collections: [{ name: 'Orders' }] }
          response2 = instance_double(SchemaResponse, body: schema2, etag: 'etag-2')

          allow(rpc_client).to receive(:fetch_schema).and_return(response1, response2)

          client.start
          sleep(1.5) # Wait for 2 polls
          client.stop

          # Should have been called with the changed schema
          expect(callback).to have_received(:call).with(schema2).at_least(:once)
        end

        it 'does not trigger callback if schema stays the same' do
          rpc_client = instance_double(RpcClient)
          allow(RpcClient).to receive(:new).and_return(rpc_client)

          client = described_class.new(uri, secret, polling_interval: 1) { |schema| callback.call(schema) }

          # Same ETag for all polls (schema unchanged)
          response = instance_double(SchemaResponse, body: schema, etag: 'etag-same')
          # First returns the response, then returns NotModified
          allow(rpc_client).to receive(:fetch_schema).and_return(response, RpcClient::NotModified)

          client.start
          sleep(1.5) # Wait for at least 2 polls
          client.stop

          # Should NOT have called callback (schema unchanged)
          expect(callback).not_to have_received(:call)
        end

        it 'continues polling after connection errors' do
          rpc_client = instance_double(RpcClient)
          allow(RpcClient).to receive(:new).and_return(rpc_client)

          client = described_class.new(uri, secret, polling_interval: 1) { |schema| callback.call(schema) }

          # First poll fails, second succeeds
          schema_response = instance_double(SchemaResponse, body: schema, etag: 'etag-123')
          call_count = 0
          allow(rpc_client).to receive(:fetch_schema) do
            call_count += 1
            raise Faraday::ConnectionFailed, 'Connection refused' if call_count == 1

            schema_response
          end

          client.start
          sleep(1.5) # Wait for 2 polls
          client.stop

          # Should have continued polling after failure
          # Initial sync fetch failure logs as 'Error', polling loop failures log as 'Warn'
          expect(logger).to have_received(:log).with('Error', /Connection failed/)
          expect(logger).to have_received(:log).with('Debug', /Initial schema loaded successfully/)
        end

        it 'stops polling when closed' do
          client = described_class.new(uri, secret, polling_interval: 1) { |schema| callback.call(schema) }

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
