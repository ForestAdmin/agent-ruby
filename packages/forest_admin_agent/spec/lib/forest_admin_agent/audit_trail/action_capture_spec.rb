require 'spec_helper'

module ForestAdminAgent
  module AuditTrail
    describe ActionCapture do
      # Rows keyed by position, which stands in for the row id the store hands back.
      let(:store) do
        Class.new do
          attr_reader :records

          def initialize
            @records = []
          end

          def append_all(rows)
            first = @records.size
            @records.concat(rows)

            (first...@records.size).to_a
          end

          def confirm(id, attributes)
            attributes.each { |key, value| @records[id][key] = value }
            @records[id][:status] = ForestAdminAgent::AuditTrail::Recording::DONE
          end
        end.new
      end

      let(:caller_double) { double('caller', id: 42, first_name: 'Ada', last_name: 'L', email: 'ada@test') }
      let(:capture) { described_class.new(store) }

      def invocation(**over)
        { caller: caller_double, collection: 'orders', action_name: 'Refund',
          form_values: { 'amount' => 30, 'reason' => 'damaged' }, record_ids: ['4'] }.merge(over)
      end

      def run(capture: described_class.new(store), result: { type: 'Success', message: 'Refunded' },
              failed: false, **over)
        ids = capture.pending(**invocation(**over))
        capture.confirm(ids, result: result, failed: failed)

        store.records
      end

      describe '#pending' do
        it 'records the run before it happens, with the form on the previous side' do
          capture.pending(**invocation)

          row = store.records.last
          expect(row.status).to eq(Recording::PENDING)
          expect(row.operation).to eq(described_class::EXECUTED)
          expect(row.action_name).to eq('Refund')
          expect(row.collection).to eq('orders')
          expect(row.record_id).to eq('4')
          expect(row.previous_values).to eq({ 'amount' => 30, 'reason' => 'damaged' })
          expect(row.new_values).to eq({})
        end

        it 'denormalises who acted, so a later rename does not rewrite history' do
          capture.pending(**invocation)

          row = store.records.last
          expect(row.user_id).to eq(42)
          expect(row.user_first_name).to eq('Ada')
          expect(row.user_last_name).to eq('L')
          expect(row.user_email).to eq('ada@test')
        end

        it 'copes with a caller carrying no identity at all' do
          capture.pending(**invocation(caller: double('caller')))

          expect(store.records.last.user_email).to be_nil
          expect(store.records.last.correlation_key).to be_nil
        end

        it 'writes one row per targeted record, sharing timestamp and correlation key' do
          ids = capture.pending(**invocation(record_ids: %w[4 7 9]))

          expect(ids.size).to eq(3)
          expect(store.records.map(&:record_id)).to eq(%w[4 7 9])
          expect(store.records.map(&:timestamp).uniq.size).to eq(1)
        end

        it 'records a run attached to no record when no target can be named' do
          capture.pending(**invocation(record_ids: []))

          expect(store.records.map(&:record_id)).to eq([described_class::NO_RECORD])
        end

        it 'masks redacted form fields, keeping the rest' do
          described_class.new(store, { 'orders' => ['reason'] }).pending(**invocation)

          expect(store.records.last.previous_values).to eq({ 'amount' => 30, 'reason' => Recording::REDACTED })
        end

        it 'does nothing without a configured store' do
          expect(described_class.new(nil).pending(**invocation)).to eq([])
        end
      end

      describe '#confirm' do
        it 'settles the row and keeps what the action answered' do
          row = run.last

          expect(row.status).to eq(Recording::DONE)
          expect(row.operation).to eq(described_class::EXECUTED)
          expect(row.new_values).to eq({ 'type' => 'Success', 'message' => 'Refunded' })
        end

        it 'marks a failed run with its own operation' do
          row = run(result: { type: 'Error', message: 'not allowed' }, failed: true).last

          expect(row.operation).to eq(described_class::FAILED)
          expect(row.new_values).to eq({ 'type' => 'Error', 'message' => 'not allowed' })
        end

        it 'leaves the answer empty when the action raised' do
          expect(run(result: nil, failed: true).last.new_values).to eq({})
        end

        # The row already says an action started; losing its answer beats reporting a failure for a run that
        # went through.
        it 'logs and swallows a store failure' do
          logger = instance_spy(Services::LoggerService)
          allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
          ids = capture.pending(**invocation)
          allow(store).to receive(:confirm).and_raise(StandardError, 'audit db is down')

          expect { capture.confirm(ids, result: {}) }.not_to raise_error
          expect(logger).to have_received(:log).with('Error', /audit db is down/)
        end
      end

      describe 'the answer it keeps' do
        # Forest's own keys, so camelCase on the wire — unlike a record's column names, which pass through.
        it 'camelCases the keys it keeps' do
          row = run(result: { type: 'File', name: 'refunds.csv', mime_type: 'text/csv' }).last

          expect(row.new_values).to eq({ 'type' => 'File', 'name' => 'refunds.csv', 'mimeType' => 'text/csv' })
        end

        it 'never keeps a file stream, a webhook body or headers, nor response headers' do
          file = run(result: { type: 'File', name: 'r.csv', stream: 'id,amount' }).last
          webhook = run(result: { type: 'Webhook', url: 'https://pay.test/refund', method: 'POST',
                                  body: { 'secret' => 'x' }, headers: { 'Authorization' => 'Bearer t' },
                                  response_headers: { 'Set-Cookie' => 'session=x' } }).last

          expect(file.new_values).to eq({ 'type' => 'File', 'name' => 'r.csv' })
          expect(webhook.new_values).to eq({ 'type' => 'Webhook', 'url' => 'https://pay.test/refund',
                                             'method' => 'POST' })
        end

        # A signed one-time token or a password in the userinfo would otherwise sit in the one table nobody
        # deletes from.
        it 'strips credentials and query tokens off a webhook url' do
          row = run(result: { type: 'Webhook', url: 'https://user:pass@pay.test/refund?token=abc#frag' }).last

          expect(row.new_values['url']).to eq('https://pay.test/refund')
        end

        it 'strips a query token off a redirect path' do
          row = run(result: { type: 'Redirect', path: '/orders/4?signature=abc' }).last

          expect(row.new_values['path']).to eq('/orders/4')
        end

        it 'still sanitises a url the parser refuses' do
          row = run(result: { type: 'Webhook', url: 'https://user:pass@pay test/refund?token=abc' }).last

          expect(row.new_values['url']).to eq('https://pay test/refund')
        end
      end
    end
  end
end
