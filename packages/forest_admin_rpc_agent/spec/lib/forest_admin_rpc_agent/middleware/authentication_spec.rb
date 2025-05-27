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

      context 'when signature is reused within allowed window' do
        before do
          env['HTTP_X_SIGNATURE'] = signature
          env['HTTP_X_TIMESTAMP'] = timestamp
          middleware.call(env)
        end

        it 'allows the request' do
          status, = middleware.call(env)
          expect(status).to eq(200)
        end
      end

      context 'when signature is reused after allowed window' do
        before do
          env['HTTP_X_SIGNATURE'] = signature
          env['HTTP_X_TIMESTAMP'] = timestamp
          middleware.call(env)
          allow(Time).to receive(:now).and_return(Time.now + described_class::SIGNATURE_REUSE_WINDOW + 1)
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
    end
  end
end
