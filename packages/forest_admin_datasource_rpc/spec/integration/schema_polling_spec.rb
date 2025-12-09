require 'spec_helper'
require 'json'
require 'openssl'

module ForestAdminDatasourceRpc
  module Integration
    describe 'Schema Polling Integration' do
      let(:uri) { 'http://localhost:3000' }
      let(:auth_secret) { 'test-secret-key' }
      let(:logger) { instance_spy(Logger) }
      let(:callback) { instance_double(Proc, call: nil) }
      let(:schema1) { { collections: [{ name: 'Products' }], charts: [] } }
      let(:schema2) { { collections: [{ name: 'Orders' }], charts: [] } }

      before do
        allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
      end

      describe 'HMAC authentication' do
        it 'generates correct HMAC signature for requests' do
          client = Utils::SchemaPollingClient.new(uri, auth_secret) { |schema| callback.call(schema) }

          timestamp = '2025-12-09T12:00:00.000Z'
          signature = client.send(:generate_signature, timestamp)

          expected = OpenSSL::HMAC.hexdigest('SHA256', auth_secret, timestamp)
          expect(signature).to eq(expected)
        end
      end

      describe 'schema polling flow' do
        it 'fetches schema and stores hash on first poll' do
          client = Utils::SchemaPollingClient.new(uri, auth_secret) { |schema| callback.call(schema) }

          http_client = instance_double(Faraday::Connection)
          client.instance_variable_set(:@http_client, http_client)

          response = instance_double(
            Faraday::Response,
            success?: true,
            status: 200,
            body: JSON.generate(schema1)
          )

          allow(http_client).to receive(:get).and_return(response)

          client.send(:check_schema)

          # Should store hash without triggering callback
          expect(client.instance_variable_get(:@last_schema_hash)).not_to be_nil
          expect(callback).not_to have_received(:call)
          expect(logger).to have_received(:log).with('Debug', '[Schema Polling] Initial schema hash stored')
        end

        it 'detects schema change and triggers callback' do
          client = Utils::SchemaPollingClient.new(uri, auth_secret) { |schema| callback.call(schema) }

          http_client = instance_double(Faraday::Connection)
          client.instance_variable_set(:@http_client, http_client)

          # First poll with schema1
          response1 = instance_double(Faraday::Response, success?: true, status: 200, body: JSON.generate(schema1))
          allow(http_client).to receive(:get).and_return(response1)
          client.send(:check_schema)

          # Second poll with schema2 (changed)
          response2 = instance_double(Faraday::Response, success?: true, status: 200, body: JSON.generate(schema2))
          allow(http_client).to receive(:get).and_return(response2)
          client.send(:check_schema)

          # Callback should have been called with new schema
          expect(callback).to have_received(:call).with(schema2)
          expect(logger).to have_received(:log).with('Info', /Schema changed detected/)
        end

        it 'does not trigger callback if schema unchanged' do
          client = Utils::SchemaPollingClient.new(uri, auth_secret) { |schema| callback.call(schema) }

          http_client = instance_double(Faraday::Connection)
          client.instance_variable_set(:@http_client, http_client)

          response = instance_double(Faraday::Response, success?: true, status: 200, body: JSON.generate(schema1))
          allow(http_client).to receive(:get).and_return(response)

          # Multiple polls with same schema
          client.send(:check_schema)
          client.send(:check_schema)
          client.send(:check_schema)

          # Callback should NOT have been called
          expect(callback).not_to have_received(:call)
          expect(logger).to have_received(:log).with('Debug', '[Schema Polling] Schema unchanged').at_least(:once)
        end

        it 'validates HMAC signature in requests' do
          client = Utils::SchemaPollingClient.new(uri, auth_secret) { |schema| callback.call(schema) }

          http_client = instance_double(Faraday::Connection)
          client.instance_variable_set(:@http_client, http_client)

          # Capture the headers sent
          captured_headers = nil
          allow(http_client).to receive(:get) do |_uri, _params, headers|
            captured_headers = headers
            instance_double(
              Faraday::Response,
              success?: true,
              status: 200,
              body: JSON.generate(schema1)
            )
          end

          client.send(:check_schema)

          # Verify HMAC headers were sent
          expect(captured_headers).to have_key('X_TIMESTAMP')
          expect(captured_headers).to have_key('X_SIGNATURE')

          # Verify signature is correct
          timestamp = captured_headers['X_TIMESTAMP']
          signature = captured_headers['X_SIGNATURE']
          expected_signature = OpenSSL::HMAC.hexdigest('SHA256', auth_secret, timestamp)

          expect(signature).to eq(expected_signature)
        end
      end

      describe 'error handling' do
        it 'handles connection failures gracefully' do
          client = Utils::SchemaPollingClient.new(uri, auth_secret) { |schema| callback.call(schema) }

          http_client = instance_double(Faraday::Connection)
          client.instance_variable_set(:@http_client, http_client)

          allow(http_client).to receive(:get).and_raise(Faraday::ConnectionFailed, 'Connection refused')

          expect { client.send(:check_schema) }.not_to raise_error

          expect(logger).to have_received(:log).with('Warn', /Connection error/)
          expect(callback).not_to have_received(:call)
        end

        it 'handles authentication failures' do
          client = Utils::SchemaPollingClient.new(uri, auth_secret) { |schema| callback.call(schema) }

          http_client = instance_double(Faraday::Connection)
          client.instance_variable_set(:@http_client, http_client)

          # Return 401 Unauthorized
          auth_error_response = instance_double(
            Faraday::Response,
            success?: false,
            status: 401,
            body: '{"error":"Unauthorized"}'
          )

          allow(http_client).to receive(:get).and_return(auth_error_response)

          expect { client.send(:check_schema) }.not_to raise_error

          expect(logger).to have_received(:log).with('Warn', /HTTP 401/)
          expect(callback).not_to have_received(:call)
        end

        it 'continues polling after errors' do
          client = Utils::SchemaPollingClient.new(uri, auth_secret, polling_interval: 1) { |schema| callback.call(schema) }

          http_client = instance_double(Faraday::Connection)
          client.instance_variable_set(:@http_client, http_client)

          # First call fails, subsequent calls succeed
          call_count = 0
          allow(http_client).to receive(:get) do
            call_count += 1
            if call_count == 1
              raise Faraday::ConnectionFailed
            else
              instance_double(Faraday::Response, success?: true, status: 200, body: JSON.generate(schema1))
            end
          end

          client.start
          sleep(1.5) # Wait for 2 polls
          client.stop

          # Should have logged error and then success
          expect(logger).to have_received(:log).with('Warn', /Connection error/)
          expect(logger).to have_received(:log).with('Debug', /Initial schema hash stored/)
        end
      end

      describe 'client lifecycle' do
        it 'starts and stops cleanly' do
          client = Utils::SchemaPollingClient.new(uri, auth_secret, polling_interval: 10) { |schema| callback.call(schema) }

          # Stub polling_loop to keep thread alive
          allow(client).to receive(:polling_loop) do
            sleep(10) unless client.closed
          end

          client.start
          sleep(0.05)

          expect(client.instance_variable_get(:@polling_thread)).to be_alive

          client.stop
          sleep(0.05)

          expect(client.closed).to be true
          expect(logger).to have_received(:log).with('Debug', '[Schema Polling] Polling stopped')
        end
      end
    end
  end
end
