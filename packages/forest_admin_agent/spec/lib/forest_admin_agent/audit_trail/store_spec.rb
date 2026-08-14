require 'spec_helper'
require 'tempfile'

module ForestAdminAgent
  module AuditTrail
    describe Store do
      let(:db) { Tempfile.new(['audit', '.sqlite3']) }
      let(:store) { described_class.new(database: { adapter: 'sqlite3', database: db.path }) }

      after do
        Sql::AuditConnectionBase.remove_connection
        db.close!
      end

      def record(over = {})
        AuditRecord.new(
          operation: 'update', collection: 'accounts', record_id: '1',
          previous_values: { 'status' => 'open' }, new_values: { 'status' => 'closed' },
          timestamp: '2026-01-02T03:04:05.000Z', user_id: 42, correlation_key: 'req-1', **over
        )
      end

      def matching_fields(fields)
        store.list_by_record(collection: 'accounts', record_id: '1', fields: fields).map(&:new_values)
      end

      def connection
        Sql::AuditConnectionBase.connection
      end

      it 'creates the audit table with the expected columns on first write' do
        store.append(record)

        expect(store.send(:model).column_names.sort).to eq(
          %w[collection correlation_key id new_values operation previous_values record_id timestamp user_id]
        )
      end

      # An action row uses the two sides for what went in and what came back.
      it 'persists a smart-action row, submitted form and answer included' do
        store.append(record(operation: 'action', previous_values: { 'amount' => 30 },
                            new_values: { 'type' => 'Success', 'message' => 'Refunded' }))

        audit = store.list_by_record(collection: 'accounts', record_id: '1').first
        expect(audit.operation).to eq('action')
        expect(audit.previous_values).to eq({ 'amount' => 30 })
        expect(audit.new_values).to eq({ 'type' => 'Success', 'message' => 'Refunded' })
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
        described_class.new(database: { adapter: 'sqlite3', database: db.path }).append(record)

        names = connection.select_values('SELECT name FROM audit_migrations ORDER BY name')
        expect(names).to eq(
          ['audit_logs:001-create-audit-logs', 'audit_logs:002-index-record-and-correlation']
        )
      end

      it 'migrates a second table in the same database instead of reading the first one as done' do
        store.append(record)
        other = described_class.new(database: { adapter: 'sqlite3', database: db.path }, table_name: 'other_logs')

        expect { other.append(record) }.not_to raise_error
        expect(other.list_by_record(collection: 'accounts', record_id: '1').size).to eq(1)
        expect(connection.indexes('other_logs').map(&:name)).to include('other_logs_record_id')
      end

      it 'binds each store to its own model class instead of mutating a shared one' do
        other = described_class.new(database: { adapter: 'sqlite3', database: db.path })
        store.append(record(correlation_key: 'main'))
        other.append(record(correlation_key: 'other'))

        # No shared mutable model: AuditLog is an abstract template, each store owns a distinct subclass.
        expect(Sql::AuditLog.abstract_class?).to be(true)
        expect(store.send(:model)).not_to equal(other.send(:model))
        expect(store.send(:model).table_name).to eq('audit_logs')
        expect(store.list_by_record(collection: 'accounts', record_id: '1').map(&:correlation_key))
          .to eq(%w[main other])
      end

      it 'lists only entries whose diff touched one of the given fields' do
        store.append(record(previous_values: { 'status' => 'open' }, new_values: { 'status' => 'closed' }))
        store.append(record(previous_values: { 'note' => 'a' }, new_values: { 'note' => 'b' }))
        # Added key: it exists on the new side only, so both sides have to be searched.
        store.append(record(previous_values: {}, new_values: { 'tags' => ['x'] }))

        expect(matching_fields(%w[status])).to eq([{ 'status' => 'closed' }])
        expect(matching_fields(%w[tags])).to eq([{ 'tags' => ['x'] }])
        expect(matching_fields(%w[status note]).size).to eq(2)
        expect(matching_fields(%w[missing])).to eq([])
      end

      it 'treats a field name holding a dot as a whole key, not a path' do
        store.append(record(previous_values: { 'address.city' => 'Paris' },
                            new_values: { 'address.city' => 'Lyon' }))
        store.append(record(previous_values: { 'address' => { 'city' => 'Paris' } },
                            new_values: { 'address' => { 'city' => 'Lyon' } }))

        expect(matching_fields(['address.city'])).to eq([{ 'address.city' => 'Lyon' }])
        expect(matching_fields(['address'])).to eq([{ 'address' => { 'city' => 'Lyon' } }])
      end

      it 'counts with the field filter applied' do
        store.append(record(previous_values: { 'status' => 'open' }, new_values: { 'status' => 'closed' }))
        store.append(record(previous_values: { 'note' => 'a' }, new_values: { 'note' => 'b' }))

        expect(store.count_by_record(collection: 'accounts', record_id: '1', fields: %w[status])).to eq(1)
      end

      it 'refuses to filter by field on an adapter it has no JSON test for' do
        store.append(record)
        allow(store.send(:model).connection).to receive(:adapter_name).and_return('Informix')

        expect { store.list_by_record(collection: 'accounts', record_id: '1', fields: %w[status]) }
          .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /not supported on informix/)
      end

      describe '#list_since' do
        it 'returns entries strictly newer than the instant, newest first' do
          store.append(record(timestamp: '2026-01-02T03:04:05.000Z', correlation_key: 'older'))
          store.append(record(timestamp: '2026-01-02T03:04:06.000Z', correlation_key: 'at'))
          store.append(record(timestamp: '2026-01-02T03:04:07.000Z', correlation_key: 'newer'))

          history = store.list_since(collection: 'accounts', record_id: '1',
                                     timestamp: '2026-01-02T03:04:06.000Z')

          expect(history.map(&:correlation_key)).to eq(['newer'])
        end

        it 'breaks ties on equal timestamps by reverse insertion order' do
          store.append(record(timestamp: '2026-01-02T03:04:07.000Z', correlation_key: 'first'))
          store.append(record(timestamp: '2026-01-02T03:04:07.000Z', correlation_key: 'second'))

          history = store.list_since(collection: 'accounts', record_id: '1',
                                     timestamp: '2026-01-02T03:04:06.000Z')

          expect(history.map(&:correlation_key)).to eq(%w[second first])
        end
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
