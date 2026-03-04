require 'spec_helper'

module ForestAdminDatasourceRpc
  module Utils
    describe SchemaPollingClient do
      let(:uri) { 'https://example.com' }
      let(:secret) { 'my-secret' }
      let(:logger) { instance_spy(Logger) }
      let(:callback) { instance_double(Proc, call: nil) }
      let(:schema) { { collections: [{ name: 'Products' }], charts: [] } }
      let(:pool) { SchemaPollingPool.instance }

      before do
        allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
        pool.reset!
      end

      after do
        pool.shutdown!
      end

      describe '#initialize' do
        it 'initializes with correct attributes' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }

          expect(client.instance_variable_get(:@uri)).to eq(uri)
          expect(client.instance_variable_get(:@auth_secret)).to eq(secret)
          expect(client.closed).to be false
          expect(client.instance_variable_get(:@current_schema)).to be_nil
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

          client.instance_variable_set(:@closed, true)

          expect(client.closed).to be true
        end

        it 'creates RPC client for schema fetching' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }

          expect(client.instance_variable_get(:@rpc_client)).to be_a(RpcClient)
        end

        it 'exposes client_id based on URI' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          expect(client.client_id).to eq(uri)
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

        context 'with introspection parameter' do
          it 'stores introspection schema when provided' do
            introspection = { collections: [], charts: [], etag: 'provided-etag-123' }
            client = described_class.new(uri, secret, introspection: introspection) { |schema| callback.call(schema) }

            expect(client.instance_variable_get(:@introspection_schema)).to eq(introspection)
          end

          it 'defaults introspection schema to nil' do
            client = described_class.new(uri, secret) { |schema| callback.call(schema) }

            expect(client.instance_variable_get(:@introspection_schema)).to be_nil
          end
        end
      end

      describe '#start' do
        let(:rpc_client) { instance_double(RpcClient) }
        let(:schema_with_etag) { schema.merge(etag: 'etag-123') }

        before do
          allow(RpcClient).to receive(:new).and_return(rpc_client)
          allow(rpc_client).to receive(:fetch_schema).and_return(schema_with_etag)
        end

        it 'registers with the pool' do
          client = described_class.new(uri, secret, polling_interval: 600) { |schema| callback.call(schema) }

          expect(pool.client_count).to eq(0)
          client.start?
          expect(pool.client_count).to eq(1)

          client.stop
        end

        it 'does not start if already closed' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          client.instance_variable_set(:@closed, true)

          result = client.start?

          expect(result).to be false
          expect(pool.client_count).to eq(0)
        end

        it 'logs registration with pool' do
          client = described_class.new(uri, secret, polling_interval: 600) { |schema| callback.call(schema) }
          client.start?

          expect(logger).to have_received(:log).with('Info', /Registered with pool/)

          client.stop
        end
      end

      describe '#stop' do
        let(:rpc_client) { instance_double(RpcClient) }
        let(:schema_with_etag) { schema.merge(etag: 'etag-123') }

        before do
          allow(RpcClient).to receive(:new).and_return(rpc_client)
          allow(rpc_client).to receive(:fetch_schema).and_return(schema_with_etag)
        end

        it 'unregisters from the pool' do
          client = described_class.new(uri, secret, polling_interval: 600) { |schema| callback.call(schema) }
          client.start?
          expect(pool.client_count).to eq(1)

          client.stop
          expect(pool.client_count).to eq(0)
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
          client = described_class.new(uri, secret, polling_interval: 600) { |schema| callback.call(schema) }
          client.start?

          client.stop

          expect(logger).to have_received(:log).with('Debug', '[Schema Polling] Stopping polling')
          expect(logger).to have_received(:log).with('Debug', '[Schema Polling] Polling stopped')
        end
      end

      describe '#check_schema' do
        let(:rpc_client) { instance_double(RpcClient) }
        let(:schema_with_etag) { schema.merge(etag: 'etag-123') }

        before do
          allow(RpcClient).to receive(:new).and_return(rpc_client)
        end

        it 'uses RpcClient to fetch schema with ETag support' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          # current_schema is nil initially, so etag is nil
          allow(rpc_client).to receive(:fetch_schema).and_return(schema_with_etag)

          client.check_schema

          expect(rpc_client).to have_received(:fetch_schema).with('/forest/rpc-schema', if_none_match: nil)
        end

        it 'stores schema with ETag on first poll without triggering callback' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          allow(rpc_client).to receive(:fetch_schema).and_return(schema_with_etag)

          client.check_schema

          expect(client.instance_variable_get(:@current_schema)).to eq(schema_with_etag)
          expect(client.current_schema[:etag]).to eq('etag-123')
          expect(callback).not_to have_received(:call)
          expect(logger).to have_received(:log).with('Info', '[Schema Polling] Initial sync completed successfully (ETag: etag-123)')
        end

        it 'sends If-None-Match header on subsequent polls' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          allow(rpc_client).to receive(:fetch_schema).and_return(schema_with_etag)

          # First poll
          client.check_schema

          # Second poll should include cached ETag
          allow(rpc_client).to receive(:fetch_schema).and_return(RpcClient::NotModified)
          client.check_schema

          expect(rpc_client).to have_received(:fetch_schema).with('/forest/rpc-schema', if_none_match: 'etag-123')
        end

        it 'detects schema change via ETag and triggers callback' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          allow(rpc_client).to receive(:fetch_schema).and_return(schema_with_etag)

          # First poll
          client.check_schema

          # Second poll with different ETag (schema changed)
          new_schema = { collections: [{ name: 'Orders' }], charts: [], etag: 'etag-456' }
          allow(rpc_client).to receive(:fetch_schema).and_return(new_schema)

          client.check_schema

          # Callback should have been called with new schema
          expect(callback).to have_received(:call).with(new_schema)
          expect(logger).to have_received(:log).with('Info', /Schema changed detected/)
          expect(client.current_schema[:etag]).to eq('etag-456')
        end

        it 'handles NotModified (304) response without triggering callback' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          allow(rpc_client).to receive(:fetch_schema).and_return(schema_with_etag)

          # First poll
          client.check_schema

          # Second poll with 304 Not Modified
          allow(rpc_client).to receive(:fetch_schema).and_return(RpcClient::NotModified)
          client.check_schema

          # Callback should not have been called
          expect(callback).not_to have_received(:call)
          expect(logger).to have_received(:log).with('Debug', '[Schema Polling] Schema unchanged (HTTP 304 Not Modified), ETag still valid: etag-123')
        end

        it 'handles connection failures gracefully' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          allow(rpc_client).to receive(:fetch_schema).and_raise(Faraday::ConnectionFailed, 'Connection refused')

          expect { client.check_schema }.not_to raise_error

          expect(logger).to have_received(:log).with('Warn', /Connection error/)
          expect(callback).not_to have_received(:call)
        end

        it 'handles timeout errors gracefully' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          allow(rpc_client).to receive(:fetch_schema).and_raise(Faraday::TimeoutError, 'Timeout')

          expect { client.check_schema }.not_to raise_error

          expect(logger).to have_received(:log).with('Warn', /Connection error/)
        end

        it 'handles authentication errors gracefully' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          allow(rpc_client).to receive(:fetch_schema).and_raise(
            ForestAdminAgent::Http::Exceptions::AuthenticationOpenIdClient, 'Auth failed'
          )

          expect { client.check_schema }.not_to raise_error

          expect(logger).to have_received(:log).with('Error', /Authentication error/)
        end

        it 'handles RPC errors (ForestException) gracefully' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          allow(rpc_client).to receive(:fetch_schema).and_raise(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            'RPC connection failed: Unable to connect to http://localhost. Please check if the RPC server is running.'
          )

          expect { client.check_schema }.not_to raise_error

          expect(logger).to have_received(:log).with('Warn', /RPC error.*RPC connection failed/)
          expect(callback).not_to have_received(:call)
        end

        it 'handles unexpected errors gracefully' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          allow(rpc_client).to receive(:fetch_schema).and_raise(StandardError, 'Unexpected error')

          expect { client.check_schema }.not_to raise_error

          expect(logger).to have_received(:log).with('Error', /Unexpected error/)
        end

        it 'increments and resets connection attempts on successful poll' do
          client = described_class.new(uri, secret) { |schema| callback.call(schema) }
          allow(rpc_client).to receive(:fetch_schema).and_return(schema_with_etag)

          # Connection attempts should be incremented then reset
          client.check_schema

          # After successful poll, connection attempts is reset to 0
          expect(client.instance_variable_get(:@connection_attempts)).to eq(0)
        end
      end

      describe '#start? with introspection' do
        let(:rpc_client) { instance_double(RpcClient) }
        let(:introspection) { { collections: [{ name: 'Products' }], charts: [], etag: 'introspection-etag-abc' } }

        before do
          allow(RpcClient).to receive(:new).and_return(rpc_client)
        end

        it 'uses introspection etag in initial fetch' do
          client = described_class.new(
            uri, secret,
            introspection: introspection
          ) { |s| callback.call(s) }

          allow(rpc_client).to receive(:fetch_schema).and_return(RpcClient::NotModified)

          client.start?
          client.stop

          expect(rpc_client).to have_received(:fetch_schema).with(
            '/forest/rpc-schema',
            if_none_match: 'introspection-etag-abc'
          )
        end

        it 'uses introspection schema on NotModified response' do
          client = described_class.new(
            uri, secret,
            introspection: introspection
          ) { |s| callback.call(s) }

          allow(rpc_client).to receive(:fetch_schema).and_return(RpcClient::NotModified)

          client.start?
          client.stop

          expect(client.current_schema).to eq(introspection)
          expect(client.current_schema[:etag]).to eq('introspection-etag-abc')
        end

        it 'uses new schema when RPC returns updated schema' do
          new_schema = { collections: [{ name: 'Orders' }], charts: [], etag: 'new-etag-456' }
          client = described_class.new(
            uri, secret,
            introspection: introspection
          ) { |s| callback.call(s) }

          allow(rpc_client).to receive(:fetch_schema).and_return(new_schema)

          client.start?
          client.stop

          expect(client.current_schema).to eq(new_schema)
          expect(client.current_schema[:etag]).to eq('new-etag-456')
        end

        it 'falls back to introspection schema on connection error' do
          client = described_class.new(
            uri, secret,
            introspection: introspection
          ) { |s| callback.call(s) }

          allow(rpc_client).to receive(:fetch_schema).and_raise(Faraday::ConnectionFailed, 'Connection refused')

          client.start?
          client.stop

          expect(client.current_schema).to eq(introspection)
          expect(client.current_schema[:etag]).to eq('introspection-etag-abc')
          expect(client.instance_variable_get(:@introspection_schema)).to be_nil
        end

        it 'falls back to introspection schema on ForestException (RPC wrapped error)' do
          client = described_class.new(
            uri, secret,
            introspection: introspection
          ) { |s| callback.call(s) }

          allow(rpc_client).to receive(:fetch_schema).and_raise(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            'RPC connection failed: Unable to connect to http://localhost.'
          )

          client.start?
          client.stop

          expect(client.current_schema).to eq(introspection)
          expect(client.current_schema[:etag]).to eq('introspection-etag-abc')
          expect(logger).to have_received(:log).with('Warn', /RPC agent.*unreachable.*ForestException/)
        end

        it 'raises error when no introspection and initial fetch fails' do
          client = described_class.new(uri, secret) { |s| callback.call(s) }

          allow(rpc_client).to receive(:fetch_schema).and_raise(Faraday::ConnectionFailed, 'Connection refused')

          expect { client.start? }.to raise_error(Faraday::ConnectionFailed)
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

      describe 'integration: polling via pool' do
        let(:rpc_client) { instance_double(RpcClient) }
        let(:schema_with_etag) { schema.merge(etag: 'etag-123') }

        before do
          allow(RpcClient).to receive(:new).and_return(rpc_client)
          allow(rpc_client).to receive(:fetch_schema).and_return(schema_with_etag)
          allow(pool).to receive(:calculate_initial_poll_time).and_return(Time.now)
        end

        it 'triggers callback on schema change via pool' do
          # First poll
          schema1 = { collections: [{ name: 'Products' }], etag: 'etag-1' }

          # Second poll with different schema
          schema2 = { collections: [{ name: 'Orders' }], etag: 'etag-2' }

          allow(rpc_client).to receive(:fetch_schema).and_return(schema1, schema2)

          client = described_class.new(uri, secret, polling_interval: 1) { |schema| callback.call(schema) }

          client.start?
          sleep(2.5) # Wait for pool scheduler to poll
          client.stop

          # Should have been called with the changed schema
          expect(callback).to have_received(:call).with(schema2).at_least(:once)
        end

        it 'does not trigger callback if schema stays the same' do
          # Same ETag for all polls (schema unchanged)
          response = schema.merge(etag: 'etag-same')
          # First returns the response, then returns NotModified
          allow(rpc_client).to receive(:fetch_schema).and_return(response, RpcClient::NotModified)

          client = described_class.new(uri, secret, polling_interval: 1) { |schema| callback.call(schema) }

          client.start?
          sleep(2.5) # Wait for pool scheduler to poll
          client.stop

          # Should NOT have called callback (schema unchanged)
          expect(callback).not_to have_received(:call)
        end

        it 'continues polling after connection errors' do
          # Initial fetch succeeds, first poll fails, second poll succeeds
          call_count = 0
          allow(rpc_client).to receive(:fetch_schema) do
            call_count += 1
            # First call is initial fetch (succeeds), second is first poll (fails), third succeeds
            raise Faraday::ConnectionFailed, 'Connection refused' if call_count == 2

            schema_with_etag
          end

          client = described_class.new(uri, secret, polling_interval: 1) { |schema| callback.call(schema) }

          client.start?
          sleep(3) # Wait for initial fetch + polling
          client.stop

          # Should have continued polling after the connection error
          expect(logger).to have_received(:log).with('Warn', /Connection error/)
        end

        it 'continues polling after RPC errors (ForestException)' do
          # Initial fetch succeeds, first poll fails with ForestException, second poll succeeds
          call_count = 0
          allow(rpc_client).to receive(:fetch_schema) do
            call_count += 1
            # First call is initial fetch (succeeds), second is first poll (fails), third succeeds
            if call_count == 2
              raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                    'RPC connection failed: Unable to connect to http://localhost.'
            end

            schema_with_etag
          end

          client = described_class.new(uri, secret, polling_interval: 1) { |schema| callback.call(schema) }

          client.start?
          sleep(3) # Wait for initial fetch + polling
          client.stop

          # Should have continued polling after the RPC error
          expect(logger).to have_received(:log).with('Warn', /RPC error.*RPC connection failed/)
        end
      end
    end
  end
end
