require 'spec_helper'

module ForestAdminAgent
  module AuditTrail
    describe ActionCapture do
      let(:store) do
        Class.new do
          attr_reader :records

          def initialize
            @records = []
          end

          def append(record)
            @records << record
          end
        end.new
      end

      let(:caller_double) { double('caller', id: 42, request_id: 'req-xyz') }

      def record(capture: described_class.new(store), **over)
        invocation = { caller: caller_double, collection: 'orders',
                       form_values: { 'amount' => 30, 'reason' => 'damaged' }, record_ids: ['4'] }
        invocation.update(over)

        capture.record(**invocation)
        store.records
      end

      it 'records the invocation against the selected record' do
        audit = record.last

        expect(audit.operation).to eq('action')
        expect(audit.collection).to eq('orders')
        expect(audit.record_id).to eq('4')
        expect(audit.user_id).to eq(42)
        expect(audit.correlation_key).to eq('req-xyz')
        expect(audit.previous_values).to eq({})
        expect(audit.new_values).to eq({ 'amount' => 30, 'reason' => 'damaged' })
      end

      it 'writes one row per selected record, sharing timestamp and correlation key' do
        records = record(record_ids: %w[4 7 9])

        expect(records.map(&:record_id)).to eq(%w[4 7 9])
        expect(records.map(&:timestamp).uniq.size).to eq(1)
        expect(records.map(&:correlation_key).uniq).to eq(['req-xyz'])
      end

      # Global actions and select-all selections name no record, but the run still has to leave a trace.
      it 'records a run attached to no record when the selection is unknown' do
        records = record(record_ids: [])

        expect(records.size).to eq(1)
        expect(records.last.record_id).to eq('')
      end

      it 'marks a failed run with its own operation' do
        expect(record(failed: true).last.operation).to eq('action_failed')
      end

      it 'masks redacted fields of the form, keeping the rest' do
        capture = described_class.new(store, { 'orders' => ['reason'] })

        audit = record(capture: capture).last

        expect(audit.new_values).to eq({ 'amount' => 30, 'reason' => Recording::REDACTED })
      end

      it 'does nothing without a configured store' do
        expect { record(capture: described_class.new(nil)) }.not_to raise_error
      end

      # The action already ran: reporting a failure for it because the audit database is down would be
      # worse than losing the row.
      it 'logs and swallows a store failure instead of breaking the action' do
        logger = instance_spy(Services::LoggerService)
        allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
        allow(store).to receive(:append).and_raise(StandardError, 'audit db is down')

        expect { record }.not_to raise_error
        expect(logger).to have_received(:log).with('Error', /audit db is down/)
      end

      it 'falls back to a generated correlation key when the caller carries none' do
        audit = record(caller: double('caller', id: 42, request_id: nil)).last

        expect(audit.correlation_key).to match(/\A[0-9a-f-]{36}\z/)
      end
    end
  end
end
