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

      context 'when multiple requests with millisecond timestamps (rapid fire)' do
        it 'allows multiple requests in the same second with different milliseconds' do
          # Simulate 3 rapid requests within the same second but with different milliseconds
          3.times do |i|
            timestamp_ms = Time.now.utc.iso8601(3)
            signature_ms = OpenSSL::HMAC.hexdigest('SHA256', secret, timestamp_ms)

            test_env = {
              'HTTP_X_SIGNATURE' => signature_ms,
              'HTTP_X_TIMESTAMP' => timestamp_ms
            }

            status, = middleware.call(test_env)
            expect(status).to eq(200), "Request #{i + 1} should succeed with millisecond timestamp"

            # Simulate a tiny delay to ensure different milliseconds
            sleep(0.002)
          end
        end

        it 'accepts concurrent requests with identical signature' do
          # The Node TS rpc-agent has no anti-replay protection; Ruby matches that behaviour
          # so parallel calls from a Node main agent don't get spuriously rejected when two
          # signatures land in the same millisecond.
          timestamp_ms = Time.now.utc.iso8601(3)
          signature_ms = OpenSSL::HMAC.hexdigest('SHA256', secret, timestamp_ms)

          env['HTTP_X_SIGNATURE'] = signature_ms
          env['HTTP_X_TIMESTAMP'] = timestamp_ms

          expect(middleware.call(env).first).to eq(200)
          expect(middleware.call(env).first).to eq(200)
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
