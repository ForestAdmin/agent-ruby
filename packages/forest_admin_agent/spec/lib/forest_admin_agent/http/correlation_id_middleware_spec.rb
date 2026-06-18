require 'spec_helper'

module ForestAdminAgent
  module Http
    describe CorrelationIdMiddleware do
      after { CorrelationId.reset! }

      it 'echoes the id generated during the request on the response header' do
        app = ->(_env) { [200, {}, [CorrelationId.current]] }

        _status, headers, body = described_class.new(app).call({})

        expect(headers[CorrelationId::HEADER]).to eq(body.first)
      end

      it 'does not set the header when no id was generated during the request' do
        app = ->(_env) { [200, {}, ['ok']] }

        _status, headers, = described_class.new(app).call({})

        expect(headers).not_to have_key(CorrelationId::HEADER)
      end

      it 'resets any leaked id before handling the request' do
        CorrelationId.current = 'stale'
        seen = 'unset'
        app = lambda do |_env|
          seen = CorrelationId.current?
          [200, {}, ['ok']]
        end

        described_class.new(app).call({})

        expect(seen).to be_nil
      end

      it 'clears the id after the request so the thread is not reused with a stale id' do
        app = ->(_env) { [200, {}, [CorrelationId.current]] }

        described_class.new(app).call({})

        expect(CorrelationId.current?).to be_nil
      end
    end
  end
end
