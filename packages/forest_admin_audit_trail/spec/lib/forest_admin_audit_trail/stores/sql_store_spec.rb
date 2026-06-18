require 'spec_helper'
require 'tempfile'

module ForestAdminAuditTrail
  module Stores
    describe SqlStore do
      let(:db) { Tempfile.new(['audit', '.sqlite3']) }
      let(:store) { described_class.new(connection_string: { adapter: 'sqlite3', database: db.path }) }

      after do
        ForestAdminAuditTrail::Sql::AuditConnectionBase.remove_connection
        db.close!
      end

      def record(over = {})
        AuditRecord.new(
          operation: 'update', collection: 'accounts', record_id: '1',
          previous_values: { 'status' => 'open' }, new_values: { 'status' => 'closed' },
          timestamp: '2026-01-02T03:04:05.000Z', user_id: 42, correlation_key: 'req-1', **over
        )
      end

      def connection
        ForestAdminAuditTrail::Sql::AuditConnectionBase.connection
      end

      it 'creates the audit table with the expected columns on first write' do
        store.append(record)

        expect(ForestAdminAuditTrail::Sql::AuditLog.column_names.sort).to eq(
          %w[collection correlation_key id new_values operation previous_values record_id timestamp user_id]
        )
      end

      it 'persists and reads back a record, decoding the JSON columns' do
        store.append(record)

        audit = store.list_by_record(collection: 'accounts', record_id: '1').first
        expect(audit.operation).to eq('update')
        expect(audit.user_id).to eq(42)
        expect(audit.previous_values).to eq({ 'status' => 'open' })
        expect(audit.new_values).to eq({ 'status' => 'closed' })
      end

      it 'returns a record history oldest-first, scoped to the record, honoring skip/limit' do
        store.append(record(timestamp: '2026-01-02T03:04:06.000Z', correlation_key: 'b'))
        store.append(record(timestamp: '2026-01-02T03:04:05.000Z', correlation_key: 'a'))
        store.append(record(record_id: '2', correlation_key: 'other'))

        history = store.list_by_record(collection: 'accounts', record_id: '1')
        expect(history.map(&:correlation_key)).to eq(%w[a b])

        page = store.list_by_record(collection: 'accounts', record_id: '1', skip: 1, limit: 1)
        expect(page.map(&:correlation_key)).to eq(['b'])
      end

      it 'sorts newest first when order is desc, breaking ties by insertion order' do
        store.append(record(timestamp: '2026-01-02T03:04:05.000Z', correlation_key: 'a'))
        store.append(record(timestamp: '2026-01-02T03:04:06.000Z', correlation_key: 'b'))
        store.append(record(timestamp: '2026-01-02T03:04:05.000Z', correlation_key: 'a2'))

        history = store.list_by_record(collection: 'accounts', record_id: '1', order: 'desc')
        expect(history.map(&:correlation_key)).to eq(%w[b a a2])
      end

      it 'filters by user_ids and inclusive timestamp range' do
        store.append(record(timestamp: '2026-01-02T03:04:05.000Z', user_id: 7, correlation_key: 'keep'))
        store.append(record(timestamp: '2026-01-02T03:04:09.000Z', user_id: 7, correlation_key: 'late'))
        store.append(record(timestamp: '2026-01-02T03:04:05.000Z', user_id: 9, correlation_key: 'other'))

        history = store.list_by_record(
          collection: 'accounts', record_id: '1', user_ids: [7],
          start_timestamp: '2026-01-02T03:04:04.000Z', end_timestamp: '2026-01-02T03:04:06.000Z'
        )
        expect(history.map(&:correlation_key)).to eq(['keep'])
      end

      it 'counts matches independently of skip/limit, respecting filters' do
        store.append(record(user_id: 7))
        store.append(record(user_id: 7))
        store.append(record(user_id: 9))

        expect(store.count_by_record(collection: 'accounts', record_id: '1')).to eq(3)
        expect(store.count_by_record(collection: 'accounts', record_id: '1', user_ids: [7])).to eq(2)
      end

      it 'lists entries under a correlation key for the record, scoped and oldest first' do
        store.append(record(record_id: '1', correlation_key: 'req-1', timestamp: '2026-01-01T00:00:02.000Z'))
        store.append(record(record_id: '1', correlation_key: 'req-1', timestamp: '2026-01-01T00:00:01.000Z'))
        store.append(record(record_id: '1', correlation_key: 'req-2'))
        store.append(record(record_id: '2', correlation_key: 'req-1'))

        history = store.list_by_correlation(collection: 'accounts', record_id: '1', correlation_key: 'req-1')
        expect(history.map(&:timestamp)).to eq(['2026-01-01T00:00:01.000Z', '2026-01-01T00:00:02.000Z'])
      end

      it 'lists a flat history across multiple correlation keys, oldest first' do
        store.append(record(correlation_key: 'a', timestamp: '2026-01-03T00:00:00.000Z'))
        store.append(record(correlation_key: 'b', timestamp: '2026-01-01T00:00:00.000Z'))
        store.append(record(correlation_key: 'a', timestamp: '2026-01-02T00:00:00.000Z'))
        store.append(record(correlation_key: 'c', timestamp: '2026-01-04T00:00:00.000Z'))

        history = store.list_by_correlations(collection: 'accounts', record_id: '1', correlation_keys: %w[a b])
        expect(history.map(&:timestamp)).to eq(
          ['2026-01-01T00:00:00.000Z', '2026-01-02T00:00:00.000Z', '2026-01-03T00:00:00.000Z']
        )
      end

      it 'returns an empty array for an empty correlation key list' do
        store.append(record(correlation_key: 'a'))

        expect(store.list_by_correlations(collection: 'accounts', record_id: '1', correlation_keys: [])).to eq([])
      end

      it 'tracks applied migrations and is idempotent across stores' do
        store.append(record)
        described_class.new(connection_string: { adapter: 'sqlite3', database: db.path }).append(record)

        names = connection.select_values('SELECT name FROM audit_migrations ORDER BY name')
        expect(names).to eq(['001-create-audit-logs', '002-index-record-and-correlation'])
      end

      it 'indexes record_id, correlation_key and user_id' do
        store.append(record)

        index_names = connection.indexes('audit_logs').map(&:name)
        expect(index_names).to include(
          'audit_logs_record_id', 'audit_logs_correlation_key', 'audit_logs_user_id'
        )
      end
    end
  end
end
