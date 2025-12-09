require 'spec_helper'
require 'json'
require 'openssl'

module ForestAdminDatasourceRpc
  module Integration
    describe 'Health Check Polling Integration' do
      let(:uri) { 'http://localhost:3000/forest/health' }
      let(:auth_secret) { 'test-secret-key' }
      let(:logger) { instance_spy(Logger) }

      before do
        allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
      end

      describe 'HMAC authentication' do
        it 'generates correct HMAC signature for requests' do
          callback = proc {}
          client = Utils::HealthCheckClient.new(uri, auth_secret, &callback)

          timestamp = '2025-12-09T12:00:00.000Z'
          signature = client.send(:generate_signature, timestamp)

          expected = OpenSSL::HMAC.hexdigest('SHA256', auth_secret, timestamp)
          expect(signature).to eq(expected)
        end
      end

      describe 'successful health check flow' do
        it 'makes authenticated request and parses successful response' do
          callback = proc {}
          client = Utils::HealthCheckClient.new(uri, auth_secret, &callback)

          http_client = instance_double(Faraday::Connection)
          client.instance_variable_set(:@http_client, http_client)

          response = instance_double(
            Faraday::Response,
            success?: true,
            status: 200,
            body: '{"status":"ok","version":"1.0.0"}'
          )

          allow(http_client).to receive(:get).and_return(response)

          result = client.send(:check_health)

          expect(result).to be true
          expect(http_client).to have_received(:get).with(uri, nil, hash_including('X_TIMESTAMP', 'X_SIGNATURE'))
        end
      end

      describe 'failure handling' do
        it 'handles connection failures' do
          callback = proc {}
          client = Utils::HealthCheckClient.new(uri, auth_secret, &callback)

          http_client = instance_double(Faraday::Connection)
          client.instance_variable_set(:@http_client, http_client)

          allow(http_client).to receive(:get).and_raise(Faraday::ConnectionFailed, 'Connection refused')

          result = client.send(:check_health)

          expect(result).to be false
          expect(logger).to have_received(:log).with('Debug', /Connection error/)
        end

        it 'handles HTTP authentication errors' do
          callback = proc {}
          client = Utils::HealthCheckClient.new(uri, auth_secret, &callback)

          http_client = instance_double(Faraday::Connection)
          client.instance_variable_set(:@http_client, http_client)

          response = instance_double(
            Faraday::Response,
            success?: false,
            status: 401,
            body: 'Unauthorized'
          )

          allow(http_client).to receive(:get).and_return(response)

          result = client.send(:check_health)

          expect(result).to be false
          expect(logger).to have_received(:log).with('Warn', /HTTP 401/)
        end
      end

      describe 'callback triggering' do
        it 'triggers callback after consecutive failures reach threshold' do
          callback_called = false
          callback = proc { callback_called = true }

          client = Utils::HealthCheckClient.new(
            uri,
            auth_secret,
            polling_interval: 30,
            failure_threshold: 3,
            &callback
          )

          # Simulate 3 consecutive failures
          client.send(:handle_failure) # 1
          expect(callback_called).to be false

          client.send(:handle_failure) # 2
          expect(callback_called).to be false

          client.send(:handle_failure) # 3 - should trigger
          expect(callback_called).to be true
        end

        it 'does not trigger callback multiple times' do
          call_count = 0
          callback = proc { call_count += 1 }

          client = Utils::HealthCheckClient.new(
            uri,
            auth_secret,
            polling_interval: 30,
            failure_threshold: 2,
            &callback
          )

          # Reach threshold
          client.instance_variable_set(:@consecutive_failures, 1)
          client.send(:handle_failure) # Should trigger

          expect(call_count).to eq(1)

          # Continue failing
          client.send(:handle_failure)
          client.send(:handle_failure)

          # Should still be 1 (not called again)
          expect(call_count).to eq(1)
        end
      end

      describe 'recovery handling' do
        it 'resets failure counter on successful health check' do
          callback = proc {}
          client = Utils::HealthCheckClient.new(uri, auth_secret, &callback)

          # Simulate failures
          client.instance_variable_set(:@consecutive_failures, 5)
          client.instance_variable_set(:@server_down_triggered, true)

          # Successful check
          client.send(:handle_success)

          expect(client.instance_variable_get(:@consecutive_failures)).to eq(0)
          expect(client.instance_variable_get(:@server_down_triggered)).to be false
        end

        it 'logs server recovery after failures' do
          callback = proc {}
          client = Utils::HealthCheckClient.new(uri, auth_secret, &callback)

          client.instance_variable_set(:@consecutive_failures, 3)

          client.send(:handle_success)

          expect(logger).to have_received(:log).with('Info', /Server is back online/)
        end
      end

      describe 'client lifecycle' do
        it 'starts and stops cleanly' do
          callback = proc {}
          client = Utils::HealthCheckClient.new(uri, auth_secret, polling_interval: 10, &callback)

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
          expect(logger).to have_received(:log).with('Debug', '[Health Check] Polling stopped')
        end
      end
    end
  end
end
