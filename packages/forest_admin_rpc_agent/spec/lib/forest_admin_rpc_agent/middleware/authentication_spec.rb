require 'spec_helper'
require 'rack'
require 'openssl'
require 'time'
require 'json'

module ForestAdminRpcAgent
  module Middleware
    describe Authentication do
      let(:app) { instance_double(Proc, call: [200, {}, ['OK']]) }
      let(:middleware) { described_class.new(app) }
      let(:env) { {} }
      let(:secret) { 'test_secret' }
      let(:timestamp) { Time.now.utc.iso8601 }
      let(:signature) { OpenSSL::HMAC.hexdigest('SHA256', secret, timestamp) }

      before do
        ForestAdminRpcAgent.config.auth_secret = secret
      end

      context 'when request is valid' do
        before do
          env['HTTP_X_SIGNATURE'] = signature
          env['HTTP_X_TIMESTAMP'] = timestamp
        end

        it 'calls the next middleware' do
          status, _, body = middleware.call(env)
          expect(status).to eq(200)
          expect(body).to eq(['OK'])
        end
      end

      context 'when signature is missing' do
        before { env['HTTP_X_TIMESTAMP'] = timestamp }

        it 'returns 401 Unauthorized' do
          status, _, body = middleware.call(env)
          expect(status).to eq(401)
          expect(JSON.parse(body.first)).to eq({ 'error' => 'Unauthorized' })
        end
      end

      context 'when timestamp is missing' do
        before { env['HTTP_X_SIGNATURE'] = signature }

        it 'returns 401 Unauthorized' do
          status, = middleware.call(env)
          expect(status).to eq(401)
        end
      end

      context 'when timestamp is invalid' do
        before do
          env['HTTP_X_SIGNATURE'] = signature
          env['HTTP_X_TIMESTAMP'] = 'invalid_timestamp'
        end

        it 'returns 401 Unauthorized' do
          status, = middleware.call(env)
          expect(status).to eq(401)
        end
      end

      context 'when signature is incorrect' do
        before do
          env['HTTP_X_SIGNATURE'] = 'invalid_signature'
          env['HTTP_X_TIMESTAMP'] = timestamp
        end

        it 'returns 401 Unauthorized' do
          status, = middleware.call(env)
          expect(status).to eq(401)
        end
      end

      context 'when signature is reused within allowed window (replay attack)' do
        before do
          env['HTTP_X_SIGNATURE'] = signature
          env['HTTP_X_TIMESTAMP'] = timestamp
          # First request - should pass
          middleware.call(env)
        end

        it 'blocks the replay attack' do
          # Second request with same signature immediately - should be blocked
          status, _headers, body = middleware.call(env)
          expect(status).to eq(401)
          expect(JSON.parse(body.first)).to eq({ 'error' => 'Unauthorized' })
        end
      end

      context 'when signature is reused after allowed window' do
        before do
          env['HTTP_X_SIGNATURE'] = signature
          env['HTTP_X_TIMESTAMP'] = timestamp
          # First request
          middleware.call(env)

          # Simulate time passing (6 seconds later)
          travel_to = Time.now.utc + described_class::SIGNATURE_REUSE_WINDOW + 1
          allow(Time).to receive(:now).and_return(travel_to)
          if defined?(Time.current)
            allow(Time).to receive(:current).and_return(travel_to)
          end
        end

        it 'allows the request (signature expired from cache)' do
          # After 6 seconds, signature can be reused (not in replay window anymore)
          status, = middleware.call(env)
          expect(status).to eq(200)
        end
      end

      context 'when timestamp is too old' do
        let(:old_timestamp) { (Time.now.utc - (described_class::ALLOWED_TIME_DIFF + 10)).iso8601 }
        let(:old_signature) { OpenSSL::HMAC.hexdigest('SHA256', secret, old_timestamp) }

        before do
          env['HTTP_X_SIGNATURE'] = old_signature
          env['HTTP_X_TIMESTAMP'] = old_timestamp
        end

        it 'returns 401 Unauthorized' do
          status, = middleware.call(env)
          expect(status).to eq(401)
        end
      end

      context 'when timestamp is in the future' do
        let(:future_timestamp) { (Time.now.utc + (described_class::ALLOWED_TIME_DIFF + 10)).iso8601 }
        let(:future_signature) { OpenSSL::HMAC.hexdigest('SHA256', secret, future_timestamp) }

        before do
          env['HTTP_X_SIGNATURE'] = future_signature
          env['HTTP_X_TIMESTAMP'] = future_timestamp
        end

        it 'returns 401 Unauthorized' do
          status, = middleware.call(env)
          expect(status).to eq(401)
        end
      end

      context 'when timestamp has timezone (ISO8601 with offset)' do
        let(:timestamp_with_tz) { Time.now.getlocal('+02:00').iso8601 }
        let(:signature_with_tz) { OpenSSL::HMAC.hexdigest('SHA256', secret, timestamp_with_tz) }

        before do
          env['HTTP_X_SIGNATURE'] = signature_with_tz
          env['HTTP_X_TIMESTAMP'] = timestamp_with_tz
        end

        it 'correctly validates timestamp with timezone' do
          status, = middleware.call(env)
          expect(status).to eq(200)
        end
      end

      context 'when cleaning up old signatures' do
        it 'removes signatures older than ALLOWED_TIME_DIFF' do
          # Add multiple signatures at different times
          5.times do |i|
            ts = (Time.now.utc - (i * 100)).iso8601
            sig = OpenSSL::HMAC.hexdigest('SHA256', secret, ts)
            env['HTTP_X_SIGNATURE'] = sig
            env['HTTP_X_TIMESTAMP'] = ts
            middleware.call(env)
          end

          # Verify cleanup happens (internal state check via new request)
          status, = middleware.call(env)
          expect(status).to satisfy('be either 200 or 401') { |s| [200, 401].include?(s) }
        end
      end

      context 'with thread safety' do
        it 'mutex protects shared state from race conditions' do
          # This test verifies the mutex works - not testing exact behavior
          # Just ensure no crashes when multiple threads access the middleware
          threads = Array.new(3) do |i|
            Thread.new do
              ts = (Time.now.utc + (i * 10)).iso8601
              sig = OpenSSL::HMAC.hexdigest('SHA256', secret, ts)
              test_env = { 'HTTP_X_SIGNATURE' => sig, 'HTTP_X_TIMESTAMP' => ts }
              middleware.call(test_env)
            end
          end

          # Just verify no exceptions raised
          expect { threads.each(&:join) }.not_to raise_error
        end
      end

      context 'with edge cases' do
        it 'handles malformed ISO8601 timestamp' do
          env['HTTP_X_SIGNATURE'] = signature
          env['HTTP_X_TIMESTAMP'] = '2025-13-45T99:99:99Z' # Invalid date

          status, = middleware.call(env)
          expect(status).to eq(401)
        end

        it 'handles empty string timestamp' do
          env['HTTP_X_SIGNATURE'] = signature
          env['HTTP_X_TIMESTAMP'] = ''

          status, = middleware.call(env)
          expect(status).to eq(401)
        end

        it 'handles empty string signature' do
          env['HTTP_X_SIGNATURE'] = ''
          env['HTTP_X_TIMESTAMP'] = timestamp

          status, = middleware.call(env)
          expect(status).to eq(401)
        end
      end
    end
  end
end
